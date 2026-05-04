import { EventEmitter } from 'events';
import { existsSync, readFileSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';
import { StdioAdapter } from './adapters/stdio-adapter.js';
import { GatewayAdapter } from './adapters/gateway-adapter.js';
import { logger } from '../utils/logger.js';

/**
 * AgentBridge: picks the right adapter per agent type and exposes a unified
 * interface. Re-emits events from the active adapter so the rest of the
 * server (message-handler, websocket-server) doesn't care which backend
 * is in use.
 *
 * Adapter selection (in order):
 *   - 'gateway' — for OpenClaw / NemoClaw agents when the daemon is
 *                 reachable (auto-detected via `~/.openclaw/openclaw.json`).
 *                 Persistent WebSocket; no spawn per turn.
 *   - 'stdio'   — generic stdin/stdout REPL (default for unknown types).
 *
 * Note: the older per-command CLI adapter was removed in favor of the
 * gateway path. The CLI invocation `openclaw agent --message ...` is itself
 * a thin RPC client to the same daemon, so the spawn cost was pure
 * overhead with no functional difference.
 */
export class AgentBridge extends EventEmitter {
    constructor(config) {
        super();
        this.config = config;
        this.adapter = null;
        this.currentAgent = null;
    }

    async start() {
        const agent = this.config.getCurrentAgent();
        if (!agent) {
            logger.error('No agent configured');
            return;
        }
        await this.startAgent(agent);
    }

    async startAgent(agent) {
        if (this.adapter) {
            await this.adapter.stop();
            this.adapter = null;
        }

        this.currentAgent = agent;
        this.adapter = this.createAdapter(agent);
        this.wireAdapterEvents();

        await this.adapter.start();
    }

    createAdapter(agent) {
        const type = agent.type || inferAdapterType(agent);
        logger.info(`Creating '${type}' adapter for agent '${agent.name}'`);

        switch (type) {
            case 'gateway':
                return new GatewayAdapter(agent);
            case 'stdio':
            default:
                return new StdioAdapter(agent);
        }
    }

    wireAdapterEvents() {
        const events = ['ready', 'closed', 'error', 'response_start', 'response_chunk', 'response_end', 'response_error'];
        for (const ev of events) {
            this.adapter.on(ev, (data) => this.emit(ev, data));
        }
    }

    async switchAgent(agentId) {
        if (this.adapter?.isProcessing) {
            throw new Error('Cannot switch agent while a command is being processed');
        }

        const newAgent = this.config.setCurrentAgent(agentId);
        logger.info(`Switching to agent: ${newAgent.name}`);

        await this.startAgent(newAgent);
        return newAgent;
    }

    async sendCommand(text, commandId) {
        if (!this.adapter) throw new Error('No adapter running');
        return this.adapter.sendCommand(text, commandId);
    }

    async cancel() {
        if (this.adapter) await this.adapter.cancel();
    }

    getStatus() {
        if (!this.adapter) {
            return { running: false, ready: false, processing: false, currentAgent: null };
        }
        return this.adapter.getStatus();
    }

    async stop() {
        if (this.adapter) {
            await this.adapter.stop();
            this.adapter = null;
        }
    }

    // Convenience accessors for backwards compatibility
    get isReady() { return this.adapter?.isReady || false; }
    get isProcessing() { return this.adapter?.isProcessing || false; }
}

function inferAdapterType(agent) {
    const cmd = (agent.command || '').toLowerCase();
    if ((cmd === 'openclaw' || cmd.endsWith('/openclaw') ||
         cmd === 'nemoclaw' || cmd.endsWith('/nemoclaw')) && gatewayAvailable()) {
        return 'gateway';
    }
    return 'stdio';
}

let _gatewayAvailableCache;
function gatewayAvailable() {
    if (_gatewayAvailableCache !== undefined) return _gatewayAvailableCache;
    const path = join(homedir(), '.openclaw', 'openclaw.json');
    if (!existsSync(path)) {
        _gatewayAvailableCache = false;
        return false;
    }
    try {
        const cfg = JSON.parse(readFileSync(path, 'utf8'));
        _gatewayAvailableCache = !!cfg?.gateway?.auth?.token;
    } catch {
        _gatewayAvailableCache = false;
    }
    return _gatewayAvailableCache;
}

// Alias for backwards compatibility
export const OpenClawBridge = AgentBridge;
