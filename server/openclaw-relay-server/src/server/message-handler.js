import { logger } from '../utils/logger.js';

export class MessageHandler {
    constructor(openclawBridge, sessionManager) {
        this.bridge = openclawBridge;
        this.sessions = sessionManager;
    }

    async handleMessage(ws, raw, session) {
        let msg;
        try {
            msg = JSON.parse(raw);
        } catch {
            this.sendError(ws, 'INVALID_JSON', 'Invalid JSON message');
            return;
        }

        logger.debug(`Message: ${msg.type} (id: ${msg.id || 'n/a'})`);

        switch (msg.type) {
            case 'command':
                return this.handleCommand(ws, msg, session);
            case 'cancel':
                return this.handleCancel(ws, msg);
            case 'ping':
                return this.handlePing(ws);
            case 'list_agents':
                return this.handleListAgents(ws, msg);
            case 'switch_agent':
                return this.handleSwitchAgent(ws, msg);
            case 'config_get':
            case 'config_set':
            case 'config_action':
            case 'logs_subscribe':
                if (this.configHandler) {
                    return this.configHandler.handleConfigMessage(ws, msg);
                }
                return this.sendError(ws, 'NOT_IMPLEMENTED', 'Config API not available');
            default:
                return this.sendError(ws, 'UNKNOWN_TYPE', `Unknown message type: ${msg.type}`);
        }
    }

    setConfig(config) {
        this.config = config;
    }

    setConfigHandler(handler) {
        this.configHandler = handler;
    }

    async handleCommand(ws, msg, session) {
        const commandId = msg.id;
        const text = msg.payload?.text;

        if (!text) {
            return this.sendError(ws, 'INVALID_COMMAND', 'Missing payload.text', commandId);
        }

        const status = this.bridge.getStatus();
        if (!status.running || !status.ready) {
            return this.sendError(ws, 'OPENCLAW_NOT_RUNNING', 'OpenClaw is not running', commandId);
        }
        if (status.processing) {
            return this.sendError(ws, 'OPENCLAW_BUSY', 'OpenClaw is processing another command', commandId);
        }

        session.addToHistory('user', text, commandId);

        const responseId = `resp-${commandId}`;
        const startTime = Date.now();
        let firstChunkAt = null;
        let fullText = '';

        const onChunk = (data) => {
            if (data.commandId === commandId) {
                if (firstChunkAt === null) firstChunkAt = Date.now();
                fullText += data.text + ' ';
                ws.send(JSON.stringify({
                    type: 'response_chunk',
                    command_id: commandId,
                    response_id: responseId,
                    payload: { text: data.text, chunk_index: data.chunkIndex || 0 }
                }));
            }
        };

        const onEnd = (data) => {
            if (data.commandId === commandId) {
                const endTime = Date.now();
                const processingTime = endTime - startTime;
                const ttfbMs = firstChunkAt !== null ? firstChunkAt - startTime : null;
                session.addToHistory('assistant', fullText.trim(), commandId);
                ws.send(JSON.stringify({
                    type: 'response_end',
                    command_id: commandId,
                    response_id: responseId,
                    payload: {
                        full_text: fullText.trim(),
                        metadata: {
                            processing_time_ms: processingTime,
                            time_to_first_chunk_ms: ttfbMs,
                            transport: this.bridge.getStatus().transport || 'unknown'
                        }
                    }
                }));
                cleanup();
            }
        };

        const onError = (data) => {
            if (data.commandId === commandId) {
                this.sendError(ws, 'OPENCLAW_ERROR', data.message, commandId);
                cleanup();
            }
        };

        const cleanup = () => {
            this.bridge.removeListener('response_chunk', onChunk);
            this.bridge.removeListener('response_end', onEnd);
            this.bridge.removeListener('response_error', onError);
        };

        this.bridge.on('response_chunk', onChunk);
        this.bridge.on('response_end', onEnd);
        this.bridge.on('response_error', onError);

        // Send response_start
        ws.send(JSON.stringify({
            type: 'response_start',
            command_id: commandId,
            response_id: responseId
        }));

        try {
            await this.bridge.sendCommand(text, commandId);
        } catch (error) {
            cleanup();
            this.sendError(ws, 'OPENCLAW_ERROR', error.message, commandId);
        }
    }

    async handleCancel(ws, msg) {
        const commandId = msg.command_id;
        logger.info(`Cancelling command: ${commandId}`);
        await this.bridge.cancel();
        ws.send(JSON.stringify({
            type: 'status',
            openclaw_status: 'ready'
        }));
    }

    handleListAgents(ws, msg) {
        if (!this.config) {
            return this.sendError(ws, 'NO_CONFIG', 'Config not available');
        }
        const agents = this.config.listAgents();
        ws.send(JSON.stringify({
            type: 'agents_list',
            request_id: msg.id,
            payload: {
                agents,
                current_agent_id: this.config.currentAgentId
            }
        }));
    }

    async handleSwitchAgent(ws, msg) {
        if (!this.config) {
            return this.sendError(ws, 'NO_CONFIG', 'Config not available');
        }
        const agentId = msg.payload?.agent_id;
        if (!agentId) {
            return this.sendError(ws, 'INVALID_REQUEST', 'Missing payload.agent_id');
        }

        try {
            const agent = await this.bridge.switchAgent(agentId);
            ws.send(JSON.stringify({
                type: 'agent_switched',
                request_id: msg.id,
                payload: {
                    success: true,
                    agent: {
                        id: agent.id,
                        name: agent.name,
                        description: agent.description
                    }
                }
            }));
        } catch (err) {
            ws.send(JSON.stringify({
                type: 'agent_switched',
                request_id: msg.id,
                payload: {
                    success: false,
                    error: err.message
                }
            }));
        }
    }

    handlePing(ws) {
        ws.send(JSON.stringify({
            type: 'pong',
            timestamp: new Date().toISOString()
        }));
    }

    sendError(ws, code, message, commandId = null) {
        const msg = { type: 'error', code, message };
        if (commandId) msg.command_id = commandId;
        ws.send(JSON.stringify(msg));
    }
}
