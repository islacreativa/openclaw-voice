const DEBUG = process.env.DEBUG === 'true' || process.env.DEBUG === '1';

function ts() {
    return new Date().toISOString();
}

export const logger = {
    info(msg) {
        console.log(`[${ts()}] INFO: ${msg}`);
    },
    warn(msg) {
        console.warn(`[${ts()}] WARN: ${msg}`);
    },
    error(msg) {
        console.error(`[${ts()}] ERROR: ${msg}`);
    },
    debug(msg) {
        if (DEBUG) console.log(`[${ts()}] DEBUG: ${msg}`);
    }
};
