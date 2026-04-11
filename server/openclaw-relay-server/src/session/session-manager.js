import { v4 as uuid } from 'uuid';
import { logger } from '../utils/logger.js';

export class SessionManager {
    constructor() {
        this.sessions = new Map();
    }

    createSession(clientId, clientInfo = {}) {
        // Check if there's a paused session for this client
        for (const [id, session] of this.sessions) {
            if (session.clientId === clientId && session.paused) {
                logger.info(`Resuming session ${id} for client ${clientId}`);
                session.paused = false;
                session.lastActive = Date.now();
                return session;
            }
        }

        const session = {
            id: uuid(),
            clientId,
            clientInfo,
            history: [],
            createdAt: Date.now(),
            lastActive: Date.now(),
            paused: false
        };

        this.sessions.set(session.id, session);
        logger.info(`Created session ${session.id} for client ${clientId}`);
        return session;
    }

    getSession(sessionId) {
        return this.sessions.get(sessionId);
    }

    pauseSession(sessionId) {
        const session = this.sessions.get(sessionId);
        if (session) {
            session.paused = true;
            logger.info(`Paused session ${sessionId}`);
        }
    }

    addToHistory(session, role, text, commandId) {
        if (!session) return;
        session.history.push({
            role,
            text,
            commandId,
            timestamp: Date.now()
        });
        session.lastActive = Date.now();
    }
}

// Extend session with convenience method
Object.defineProperty(Object.prototype, '_sessionAddHistory', {
    value: undefined,
    writable: true,
    configurable: true
});

// Attach addToHistory to session objects created by SessionManager
SessionManager.prototype._patchSession = function(session) {
    session.addToHistory = (role, text, commandId) => {
        this.addToHistory(session, role, text, commandId);
    };
    return session;
};

// Override createSession to patch
const _origCreate = SessionManager.prototype.createSession;
SessionManager.prototype.createSession = function(clientId, clientInfo) {
    const session = _origCreate.call(this, clientId, clientInfo);
    return this._patchSession(session);
};
