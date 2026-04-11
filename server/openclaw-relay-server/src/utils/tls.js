import selfsigned from 'selfsigned';
import { existsSync, writeFileSync, readFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { logger } from './logger.js';

export function generateCerts(certsPath) {
    const certFile = join(certsPath, 'cert.pem');
    const keyFile = join(certsPath, 'key.pem');

    if (existsSync(certFile) && existsSync(keyFile)) {
        logger.info('TLS certificates found');
        return {
            cert: readFileSync(certFile, 'utf8'),
            key: readFileSync(keyFile, 'utf8')
        };
    }

    logger.info('Generating self-signed TLS certificates...');

    if (!existsSync(certsPath)) {
        mkdirSync(certsPath, { recursive: true });
    }

    const attrs = [{ name: 'commonName', value: 'OpenClaw Relay' }];
    const pems = selfsigned.generate(attrs, {
        days: 365,
        keySize: 2048
    });

    writeFileSync(certFile, pems.cert);
    writeFileSync(keyFile, pems.private);

    logger.info('TLS certificates generated');
    return { cert: pems.cert, key: pems.private };
}
