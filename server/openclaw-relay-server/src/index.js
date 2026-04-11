import { Config } from './config.js';
import { WebSocketServer } from './server/websocket-server.js';
import { OpenClawBridge } from './openclaw/bridge.js';
import { SessionManager } from './session/session-manager.js';
import { showSetupQR } from './utils/qr-setup.js';
import { logger } from './utils/logger.js';

async function main() {
    logger.info('Starting OpenClaw Relay Server...');

    const config = new Config();
    const sessionManager = new SessionManager();
    const openclawBridge = new OpenClawBridge(config);

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
        authToken: config.authToken
    });

    await server.start();

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
