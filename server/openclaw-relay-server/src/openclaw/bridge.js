import { EventEmitter } from 'events';
import { existsSync, readFileSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';
import { OpenClawAdapter } from './adapters/openclaw-adapter.js';
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
 *   - 'gateway'   — explicit `agent.type: 'gateway'` or auto-detected when
 *                   `~/.openclaw/openclaw.json` exists with a gateway token
 *                   (no spawn per turn — persistent WebSocket to the daemon)
 *   - 'openclaw'  — invokes `openclaw agent --message "..." --json` (cold
 *                   spawn per turn; fallback when gateway isn't available)
 *   - 'nemoclaw'  — same pattern, different command
 *   - 'stdio'     — generic stdin/stdout REPL (default for unknown types)
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
            case 'openclaw':
            case 'nemoclaw':
                return new OpenClawAdapter(agent);
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
    if (cmd === 'openclaw' || cmd.endsWith('/openclaw')) {
        // Prefer the persistent WebSocket gateway when its config exists.
        // Drops cold-spawn latency from ~1-2s/turn to handshake-only.
        if (gatewayAvailable()) return 'gateway';
        return 'openclaw';
    }
    if (cmd === 'nemoclaw' || cmd.endsWith('/nemoclaw')) {
        if (gatewayAvailable()) return 'gateway';
        return 'nemoclaw';
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
