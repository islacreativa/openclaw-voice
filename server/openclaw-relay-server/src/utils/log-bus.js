import { EventEmitter } from 'events';

const MAX_BUFFER = 500;

export class LogBus extends EventEmitter {
    constructor() {
        super();
        this.setMaxListeners(50);
        this.buffer = [];
        this.installed = false;
    }

    install() {
        if (this.installed) return;
        this.installed = true;
        const original = {
            log: console.log.bind(console),
            warn: console.warn.bind(console),
            error: console.error.bind(console),
            info: console.info ? console.info.bind(console) : console.log.bind(console)
        };

        const capture = (level, source) => (...args) => {
            const message = args.map(stringifyArg).join(' ');
            this.publish({ level, source, message });
            original[level === 'warn' ? 'warn' : level === 'error' ? 'error' : 'log'](...args);
        };

        console.log = capture('info', 'relay');
        console.info = capture('info', 'relay');
        console.warn = capture('warn', 'relay');
        console.error = capture('error', 'relay');
    }

    publish({ level = 'info', source = 'relay', message = '', metadata = null }) {
        const entry = {
            level,
            source,
            message: stripTimestamp(message),
            timestamp: new Date().toISOString(),
            metadata
        };
        this.buffer.push(entry);
        if (this.buffer.length > MAX_BUFFER) {
            this.buffer.splice(0, this.buffer.length - MAX_BUFFER);
        }
        this.emit('entry', entry);
    }

    recent({ source, level, lines = 100 } = {}) {
        const levels = ['debug', 'info', 'warn', 'error'];
        const minIdx = level ? Math.max(0, levels.indexOf(level)) : 0;
        const filtered = this.buffer.filter((e) => {
            if (source && e.source !== source) return false;
            if (level && levels.indexOf(e.level) < minIdx) return false;
            return true;
        });
        return filtered.slice(-lines);
    }

    clear() {
        this.buffer = [];
    }
}

function stringifyArg(arg) {
    if (typeof arg === 'string') return arg;
    try {
        return JSON.stringify(arg);
    } catch {
        return String(arg);
    }
}

function stripTimestamp(message) {
    return message.replace(/^\[\d{4}-\d{2}-\d{2}T[^\]]+\]\s+(?:INFO|WARN|ERROR|DEBUG):\s+/i, '');
}

export const logBus = new LogBus();
