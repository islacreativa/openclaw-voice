import { createServer } from 'https';
import { WebSocketServer as WSServer } from 'ws';
import { v4 as uuid } from 'uuid';
import { Auth } from './auth.js';
import { MessageHandler } from './message-handler.js';
import { attachHttpApi } from './http-api.js';
import { logger } from '../utils/logger.js';
import { generateCerts } from '../utils/tls.js';

export class WebSocketServer {
    constructor({ port, certsPath, openclawBridge, sessionManager, authToken, config }) {
        this.port = port;
        this.certsPath = certsPath;
        this.bridge = openclawBridge;
        this.sessionManager = sessionManager;
        this.config = config;
        this.auth = new Auth(authToken);
        this.messageHandler = new MessageHandler(openclawBridge, sessionManager);
        this.messageHandler.setConfig(config);
        this.clients = new Map();
    }

    setConfigHandler(handler) {
        this.messageHandler.setConfigHandler(handler);
    }

    async start() {
        const { cert, key } = generateCerts(this.certsPath);

        const httpsServer = createServer({ cert, key });

        // Attach OpenAI-compatible HTTP API for ElevenLabs Custom LLM.
        // Attached before `ws` adds its upgrade handler so regular
        // HTTP requests get routed to our endpoints.
        attachHttpApi(httpsServer, {
            bridge: this.bridge,
            authToken: this.auth.expectedToken,
            config: this.config
        });

        this.wss = new WSServer({ server: httpsServer });

        this.wss.on('connection', (ws) => {
            const clientId = uuid();
            logger.info(`New connection: ${clientId}`);

            const clientState = {
                id: clientId,
                authenticated: false,
                session: null,
                heartbeatTimer: null
            };
            this.clients.set(clientId, { ws, state: clientState });

            // Auth timeout — must authenticate within 10s
            const authTimeout = setTimeout(() => {
                if (!clientState.authenticated) {
                    logger.warn(`Client ${clientId} auth timeout`);
                    ws.close(4001, 'Authentication timeout');
                }
            }, 10000);

            ws.on('message', async (data) => {
                const raw = data.toString();
                let msg;
                try {
                    msg = JSON.parse(raw);
                } catch {
                    ws.send(JSON.stringify({ type: 'error', code: 'INVALID_JSON', message: 'Invalid JSON' }));
                    return;
                }

                // Handle auth
                if (!clientState.authenticated) {
                    if (msg.type !== 'auth') {
                        ws.send(JSON.stringify({ type: 'error', code: 'AUTH_REQUIRED', message: 'Must authenticate first' }));
                        return;
                    }

                    const result = this.auth.handleAuthMessage(msg);
                    if (!result.valid) {
                        ws.send(JSON.stringify({ type: 'auth_error', code: result.code, message: result.message }));
                        ws.close(4003, 'Authentication failed');
                        return;
                    }

                    clearTimeout(authTimeout);
                    clientState.authenticated = true;
                    clientState.session = this.sessionManager.createSession(clientId, msg.client_info);

                    const agent = this.config?.getCurrentAgent();
                    ws.send(JSON.stringify({
                        type: 'auth_ok',
                        session_id: clientState.session.id,
                        server_info: {
                            version: '0.1.0',
                            current_agent: agent ? { id: agent.id, name: agent.name } : null,
                            available_agents: this.config?.listAgents() || []
                        }
                    }));

                    const status = this.bridge.getStatus();
                    ws.send(JSON.stringify({
                        type: 'status',
                        openclaw_status: status.ready ? 'ready' : 'not_running',
                        details: status
                    }));

                    // Start heartbeat monitoring
                    this.startHeartbeat(clientId, ws);
                    return;
                }

                // Handle regular messages
                await this.messageHandler.handleMessage(ws, raw, clientState.session);
            });

            ws.on('close', () => {
                logger.info(`Client disconnected: ${clientId}`);
                if (clientState.heartbeatTimer) {
                    clearInterval(clientState.heartbeatTimer);
                }
                if (clientState.session) {
                    this.sessionManager.pauseSession(clientState.session.id);
                }
                this.clients.delete(clientId);
            });

            ws.on('error', (err) => {
                logger.error(`WebSocket error for ${clientId}: ${err.message}`);
            });
        });

        return new Promise((resolve) => {
            httpsServer.listen(this.port, '0.0.0.0', () => {
                logger.info(`WebSocket server listening on wss://0.0.0.0:${this.port}`);
                resolve();
            });
        });
    }

    startHeartbeat(clientId, ws) {
        const client = this.clients.get(clientId);
        if (!client) return;

        client.state.heartbeatTimer = setInterval(() => {
            if (ws.readyState === ws.OPEN) {
                ws.ping();
            }
        }, 15000);
    }
}
