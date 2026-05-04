import { EventEmitter } from 'events';
import { randomUUID } from 'crypto';
import { existsSync, readFileSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';
import { WebSocket } from 'ws';
import { logger } from '../../utils/logger.js';
import { logBus } from '../../utils/log-bus.js';

const PROTOCOL_VERSION = 3;
const RECONNECT_BASE_MS = 1_000;
const RECONNECT_MAX_MS = 30_000;
const REQUEST_TIMEOUT_MS = 30_000;

/**
 * Gateway adapter: opens a single, persistent WebSocket to the OpenClaw
 * Gateway daemon (`openclaw daemon`) and dispatches commands as `agent`
 * RPCs. Eliminates the ~1-2s cold spawn penalty of the per-command CLI
 * adapter, and surfaces real streaming chunks from the server's `agent`
 * stream events.
 *
 * Auth model: trusted same-process backend client (`client.mode: "backend"`,
 * `client.id: "gateway-client"`) on direct loopback with the shared gateway
 * token. The gateway lets us connect without device identity / pairing for
 * this exact path.
 *
 * Config (per-agent or auto-detected from ~/.openclaw/openclaw.json):
 *   url        — WS URL, defaults to ws://127.0.0.1:<port>
 *   port       — gateway port (default 18789)
 *   token      — shared auth token (default: read from openclaw.json)
 *   sessionKey — session to address (default 'agent:main:main')
 *   agentId    — optional explicit agentId override
 */
export class GatewayAdapter extends EventEmitter {
    constructor(agent) {
        super();
        this.agent = agent;
        this.isReady = false;
        this.isProcessing = false;
        this.currentCommandId = null;
        this.currentRunId = null;
        this.runs = new Map(); // runId -> { commandId, fullText, hasEmittedFirstChunk }
        this.ws = null;
        this.pending = new Map(); // requestId -> { resolve, reject, method, timer }
        this.reconnectAttempt = 0;
        this.shouldRun = false;
        this.connectPromise = null;

        this.url = agent.url || this.detectUrl();
        this.token = agent.token || this.detectToken();
        this.sessionKey = agent.sessionKey || 'agent:main:main';
        this.agentId = agent.agentId; // optional
    }

    detectUrl() {
        const port = this.agent.port || this.readGatewayConfig()?.gateway?.port || 18789;
        return `ws://127.0.0.1:${port}`;
    }

    detectToken() {
        return this.readGatewayConfig()?.gateway?.auth?.token || null;
    }

    readGatewayConfig() {
        if (this._cachedConfig !== undefined) return this._cachedConfig;
        const path = join(homedir(), '.openclaw', 'openclaw.json');
        if (!existsSync(path)) {
            this._cachedConfig = null;
            return null;
        }
        try {
            this._cachedConfig = JSON.parse(readFileSync(path, 'utf8'));
        } catch (err) {
            logger.warn(`[Gateway] Could not read openclaw.json: ${err.message}`);
            this._cachedConfig = null;
        }
        return this._cachedConfig;
    }

    async start() {
        this.shouldRun = true;
        try {
            await this.connect();
            this.isReady = true;
            this.emit('ready', { agent: this.agent.id });
            logger.info(`[Gateway] Adapter ready (url: ${this.url}, session: ${this.sessionKey})`);
        } catch (err) {
            this.isReady = false;
            logger.error(`[Gateway] Failed to start: ${err.message}`);
            this.emit('error', { message: err.message });
            throw err;
        }
    }

    async stop() {
        this.shouldRun = false;
        this.isReady = false;
        this.isProcessing = false;
        if (this.ws) {
            try { this.ws.close(); } catch {}
            this.ws = null;
        }
        for (const [, pending] of this.pending) {
            clearTimeout(pending.timer);
            pending.reject(new Error('Gateway adapter stopped'));
        }
        this.pending.clear();
        this.runs.clear();
    }

    async connect() {
        if (!this.token) throw new Error('No gateway token (set agent.token or run `openclaw configure`)');
        if (this.connectPromise) return this.connectPromise;

        this.connectPromise = new Promise((resolve, reject) => {
            const ws = new WebSocket(this.url);
            this.ws = ws;
            let opened = false;
            let timer = setTimeout(() => {
                if (!opened) {
                    try { ws.close(); } catch {}
                    reject(new Error(`Gateway handshake timed out after ${REQUEST_TIMEOUT_MS}ms`));
                }
            }, REQUEST_TIMEOUT_MS);

            ws.on('open', () => { /* wait for connect.challenge */ });

            ws.on('message', async (data) => {
                let msg;
                try {
                    msg = JSON.parse(data.toString());
                } catch {
                    return;
                }
                if (msg.type === 'event' && msg.event === 'connect.challenge') {
                    try {
                        await this.sendConnect();
                        opened = true;
                        clearTimeout(timer);
                        this.reconnectAttempt = 0;
                        resolve();
                    } catch (err) {
                        clearTimeout(timer);
                        reject(err);
                    }
                    return;
                }
                this.handleMessage(msg);
            });

            ws.on('close', (code, reason) => {
                this.handleDisconnect(code, reason?.toString());
                if (!opened) {
                    clearTimeout(timer);
                    reject(new Error(`Gateway closed before handshake (code ${code})`));
                }
            });

            ws.on('error', (err) => {
                if (!opened) {
                    clearTimeout(timer);
                    reject(err);
                } else {
                    logger.warn(`[Gateway] WS error: ${err.message}`);
                }
            });
        }).finally(() => { this.connectPromise = null; });

        return this.connectPromise;
    }

    async sendConnect() {
        const result = await this.request('connect', {
            minProtocol: PROTOCOL_VERSION,
            maxProtocol: PROTOCOL_VERSION,
            client: {
                id: 'gateway-client',
                version: '0.1.0',
                platform: 'macos',
                mode: 'backend'
            },
            role: 'operator',
            scopes: ['operator.read', 'operator.write'],
            caps: [],
            commands: [],
            permissions: {},
            auth: { token: this.token },
            locale: 'en-US',
            userAgent: 'openclaw-voice-relay/0.1.0'
        });
        if (!result?.type || result.type !== 'hello-ok') {
            throw new Error('Unexpected connect response');
        }
    }

    /** Promise-based RPC. */
    request(method, params) {
        return new Promise((resolve, reject) => {
            const id = randomUUID();
            const timer = setTimeout(() => {
                this.pending.delete(id);
                reject(new Error(`Gateway ${method} timed out`));
            }, REQUEST_TIMEOUT_MS);
            this.pending.set(id, { resolve, reject, method, timer });
            try {
                this.ws.send(JSON.stringify({ type: 'req', id, method, params }));
            } catch (err) {
                clearTimeout(timer);
                this.pending.delete(id);
                reject(err);
            }
        });
    }

    handleMessage(msg) {
        if (msg.type === 'res') {
            const pending = this.pending.get(msg.id);
            if (!pending) return;
            this.pending.delete(msg.id);
            clearTimeout(pending.timer);
            if (msg.ok) pending.resolve(msg.payload);
            else pending.reject(new Error(msg.error?.message || 'Gateway request failed'));
            return;
        }

        if (msg.type !== 'event') return;

        // Filter noise
        if (msg.event === 'tick' || msg.event === 'heartbeat' || msg.event === 'presence' ||
            msg.event === 'health' || msg.event === 'connect.challenge') return;

        // Stream agent events for the runs we care about
        if (msg.event === 'agent') {
            this.handleAgentEvent(msg.payload);
        }
    }

    handleAgentEvent(payload) {
        if (!payload) return;
        const runId = payload.runId;
        const run = this.runs.get(runId);
        if (!run) return;

        if (payload.stream === 'assistant') {
            const text = payload.data?.delta ?? payload.data?.text;
            if (text) {
                run.fullText += (run.fullText ? '' : '') + text;
                this.emit('response_chunk', {
                    commandId: run.commandId,
                    text,
                    chunkIndex: run.chunkIndex++
                });
            }
            return;
        }

        if (payload.stream === 'lifecycle') {
            const phase = payload.data?.phase;
            if (phase === 'start') {
                if (!run.startEmitted) {
                    run.startEmitted = true;
                    this.emit('response_start', { commandId: run.commandId });
                }
                return;
            }
            if (phase === 'end') {
                this.runs.delete(runId);
                if (this.runs.size === 0) this.isProcessing = false;
                if (payload.data?.aborted) {
                    this.emit('response_error', {
                        commandId: run.commandId,
                        message: 'Aborted'
                    });
                } else {
                    this.emit('response_end', {
                        commandId: run.commandId,
                        fullText: run.fullText
                    });
                }
                return;
            }
        }

        if (payload.stream === 'error') {
            this.runs.delete(runId);
            if (this.runs.size === 0) this.isProcessing = false;
            this.emit('response_error', {
                commandId: run.commandId,
                message: payload.data?.message || 'Agent error'
            });
        }
    }

    async sendCommand(text, commandId) {
        if (!this.isReady) throw new Error('Gateway adapter not ready');
        // Each agent run gets its own runId, so the gateway happily handles
        // multiple turns in parallel. ElevenLabs' Custom LLM in particular
        // fires 2-3 simultaneous /v1/chat/completions requests when starting
        // a session — refusing them with "busy" used to drop the response.
        // We track concurrency via the runs map; isProcessing reflects
        // whether ANY run is in flight (for status display only).

        this.isProcessing = true;

        const params = {
            message: text,
            idempotencyKey: randomUUID(),
            sessionKey: this.sessionKey
        };
        if (this.agentId) params.agentId = this.agentId;

        this.emit('response_start', { commandId });
        logBus.publish({
            level: 'info',
            source: 'openclaw',
            message: `Command via Gateway: "${text.substring(0, 60)}…"`,
            metadata: { commandId }
        });

        try {
            const result = await this.request('agent', params);
            const runId = result?.runId;
            if (!runId) throw new Error('Gateway agent response missing runId');
            this.currentRunId = runId;
            this.runs.set(runId, {
                commandId,
                fullText: '',
                chunkIndex: 0,
                startEmitted: true   // we already emitted response_start above
            });
        } catch (err) {
            if (this.runs.size === 0) this.isProcessing = false;
            logger.error(`[Gateway] sendCommand failed: ${err.message}`);
            logBus.publish({ level: 'error', source: 'openclaw', message: err.message });
            this.emit('response_error', { commandId, message: err.message });
        }
    }

    async cancel(commandId) {
        // Find the run by commandId so per-request cancel works under
        // concurrent load.
        let target = null;
        for (const [runId, run] of this.runs) {
            if (!commandId || run.commandId === commandId) {
                target = { runId, run };
                break;
            }
        }
        if (!target) return;
        try {
            await this.request('sessions.abort', { runId: target.runId });
        } catch (err) {
            logger.warn(`[Gateway] cancel failed: ${err.message}`);
        }
    }

    handleDisconnect(code, reason) {
        if (!this.shouldRun) return;
        this.isReady = false;
        this.isProcessing = false;

        // Reject any in-flight RPCs
        for (const [, pending] of this.pending) {
            clearTimeout(pending.timer);
            pending.reject(new Error('Gateway disconnected'));
        }
        this.pending.clear();

        this.reconnectAttempt += 1;
        const delay = Math.min(RECONNECT_BASE_MS * Math.pow(2, this.reconnectAttempt - 1), RECONNECT_MAX_MS);
        logger.warn(`[Gateway] Disconnected (code=${code} reason=${reason || 'n/a'}); reconnecting in ${delay}ms`);
        setTimeout(() => {
            if (!this.shouldRun) return;
            this.connect()
                .then(() => {
                    this.isReady = true;
                    this.emit('ready', { agent: this.agent.id });
                })
                .catch((err) => {
                    logger.error(`[Gateway] Reconnect failed: ${err.message}`);
                    this.emit('error', { message: err.message });
                });
        }, delay);
    }

    getStatus() {
        return {
            running: this.ws !== null,
            ready: this.isReady,
            processing: this.isProcessing,
            currentAgent: { id: this.agent.id, name: this.agent.name },
            sessionKey: this.sessionKey,
            transport: 'gateway-ws'
        };
    }
}
