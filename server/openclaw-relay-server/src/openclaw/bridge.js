import { EventEmitter } from 'events';
import { OpenClawAdapter } from './adapters/openclaw-adapter.js';
import { StdioAdapter } from './adapters/stdio-adapter.js';
import { logger } from '../utils/logger.js';

/**
 * AgentBridge: picks the right adapter per agent type and exposes a unified
 * interface. Re-emits events from the active adapter so the rest of the
 * server (message-handler, websocket-server) doesn't care which backend
 * is in use.
 *
 * Agent types:
 *   - 'openclaw' — invokes `openclaw agent --message "..." --json`
 *   - 'nemoclaw' — same pattern, different command
 *   - 'stdio'    — generic stdin/stdout REPL (default for unknown types)
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
    if (cmd === 'openclaw' || cmd.endsWith('/openclaw')) return 'openclaw';
    if (cmd === 'nemoclaw' || cmd.endsWith('/nemoclaw')) return 'nemoclaw';
    return 'stdio';
}

// Alias for backwards compatibility
export const OpenClawBridge = AgentBridge;
