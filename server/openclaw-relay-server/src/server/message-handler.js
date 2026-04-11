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
            case 'config_get':
            case 'config_set':
            case 'config_action':
            case 'logs_subscribe':
                // Forward to config handler if available
                if (this.configHandler) {
                    return this.configHandler.handleConfigMessage(ws, msg);
                }
                return this.sendError(ws, 'NOT_IMPLEMENTED', 'Config API not available');
            default:
                return this.sendError(ws, 'UNKNOWN_TYPE', `Unknown message type: ${msg.type}`);
        }
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
        let fullText = '';

        const onChunk = (data) => {
            if (data.commandId === commandId) {
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
                const processingTime = Date.now() - startTime;
                session.addToHistory('assistant', fullText.trim(), commandId);
                ws.send(JSON.stringify({
                    type: 'response_end',
                    command_id: commandId,
                    response_id: responseId,
                    payload: {
                        full_text: fullText.trim(),
                        metadata: { processing_time_ms: processingTime }
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
