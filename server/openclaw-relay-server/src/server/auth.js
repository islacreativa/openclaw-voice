import { logger } from '../utils/logger.js';

export class Auth {
    constructor(expectedToken) {
        this.expectedToken = expectedToken;
    }

    validate(token) {
        if (!token || typeof token !== 'string') {
            return { valid: false, code: 'AUTH_FAILED', message: 'Token missing' };
        }
        if (token !== this.expectedToken) {
            return { valid: false, code: 'INVALID_TOKEN', message: 'Invalid token' };
        }
        return { valid: true };
    }

    handleAuthMessage(msg) {
        const token = msg.token;
        const result = this.validate(token);
        if (result.valid) {
            logger.info(`Client authenticated (device: ${msg.client_info?.device || 'unknown'})`);
        } else {
            logger.warn(`Auth failed: ${result.code}`);
        }
        return result;
    }
}
