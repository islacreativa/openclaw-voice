import { Config } from './config.js';
import { WebSocketServer } from './server/websocket-server.js';
import { AgentBridge } from './openclaw/bridge.js';
import { SessionManager } from './session/session-manager.js';
import { ConfigHandler } from './server/config-handler.js';
import { showSetupQR } from './utils/qr-setup.js';
import { logger } from './utils/logger.js';
import { logBus } from './utils/log-bus.js';

async function main() {
    // Capture console output into the log bus so the iOS app can stream logs.
    logBus.install();

    logger.info('Starting OpenClaw Voice Relay Server...');

    const config = new Config();
    const sessionManager = new SessionManager();
    const openclawBridge = new AgentBridge(config);
    const relayStartedAt = Date.now();

    // Log configured agents
    logger.info(`Configured agents: ${config.agents.map(a => a.name).join(', ')}`);
    logger.info(`Current agent: ${config.getCurrentAgent()?.name}`);

    // Start OpenClaw bridge
    await openclawBridge.start();

    openclawBridge.on('ready', () => {
        logger.info('OpenClaw is ready to receive commands');
    });

    openclawBridge.on('closed', (code) => {
        logger.warn(`OpenClaw closed with code ${code}`);
    });

    // Start WebSocket server
    const server = new WebSocketServer({
        port: config.port,
        certsPath: config.certsPath,
        openclawBridge,
        sessionManager,
        authToken: config.authToken,
        config
    });

    await server.start();

    // Wire config handler (Remote Config API)
    const configHandler = new ConfigHandler({
        bridge: openclawBridge,
        config,
        sessionManager,
        server,
        relayStartedAt
    });
    server.setConfigHandler(configHandler);

    // Show connection info
    showSetupQR(config);

    console.log(`\nOpenClaw Relay Server running on wss://0.0.0.0:${config.port}`);
    console.log('Waiting for connections from OpenClaw Voice app...\n');

    // Graceful shutdown
    const shutdown = async () => {
        logger.info('Shutting down...');
        await openclawBridge.stop();
        process.exit(0);
    };

    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
}

main().catch((err) => {
    logger.error(`Fatal: ${err.message}`);
    console.error(err);
    process.exit(1);
});
