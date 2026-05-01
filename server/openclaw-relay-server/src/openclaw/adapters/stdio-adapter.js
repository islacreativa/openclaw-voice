import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import readline from 'readline';
import { logger } from '../../utils/logger.js';
import { logBus } from '../../utils/log-bus.js';

/**
 * Generic stdin/stdout REPL adapter. Spawns the agent once and streams
 * line-by-line. Detects end-of-response by prompt patterns or silence timeout.
 *
 * Use for any CLI tool that behaves as an interactive REPL (e.g. `cat`,
 * custom REPL wrappers, llm-cli tools, etc.).
 */
export class StdioAdapter extends EventEmitter {
    constructor(agent) {
        super();
        this.agent = agent;
        this.process = null;
        this.isReady = false;
        this.isProcessing = false;
        this.currentCommandId = null;
        this.responseBuffer = '';
        this.silenceTimer = null;
        this.chunkIndex = 0;
        this.silenceTimeout = agent.silenceTimeout || 2000;
    }

    async start() {
        logger.info(`Starting stdio agent '${this.agent.name}': ${this.agent.command}`);

        try {
            this.process = spawn(this.agent.command, this.agent.args || [], {
                cwd: this.agent.workdir,
                env: { ...process.env, ...(this.agent.env || {}) },
                stdio: ['pipe', 'pipe', 'pipe']
            });
        } catch (err) {
            logger.error(`Failed to spawn '${this.agent.name}': ${err.message}`);
            this.isReady = false;
            this.emit('error', { message: err.message });
            return;
        }

        const rl = readline.createInterface({
            input: this.process.stdout,
            crlfDelay: Infinity
        });
        rl.on('line', (line) => this.handleOutputLine(line));

        this.process.stderr.on('data', (data) => {
            const text = data.toString().trim();
            if (text) {
                logger.debug(`[${this.agent.name}] stderr: ${text}`);
                logBus.publish({ level: 'warn', source: this.agent.id || 'agent', message: text });
            }
        });

        this.process.on('close', (code) => {
            logger.warn(`Agent '${this.agent.name}' exited with code ${code}`);
            this.isReady = false;
            this.isProcessing = false;
            this.emit('closed', code);
            if (code !== 0 && code !== null) {
                setTimeout(() => this.start(), 2000);
            }
        });

        this.isReady = true;
        this.emit('ready', { agent: this.agent.id });
    }

    async sendCommand(text, commandId) {
        if (!this.isReady) throw new Error(`Agent '${this.agent.name}' not ready`);
        if (this.isProcessing) throw new Error('Agent is busy');

        this.isProcessing = true;
        this.currentCommandId = commandId;
        this.responseBuffer = '';
        this.chunkIndex = 0;

        this.process.stdin.write(text + '\n');
        this.emit('response_start', { commandId });
        this.resetSilenceTimer();
    }

    handleOutputLine(line) {
        const trimmed = line.trim();
        if (!trimmed) return;

        if (this.isPromptLine(trimmed)) {
            this.finishResponse();
            return;
        }

        if (this.isProcessing && this.currentCommandId) {
            this.responseBuffer += (this.responseBuffer ? ' ' : '') + trimmed;
            this.emit('response_chunk', {
                commandId: this.currentCommandId,
                text: trimmed,
                chunkIndex: this.chunkIndex++
            });
            this.resetSilenceTimer();
        }
    }

    isPromptLine(line) {
        const patterns = [/^>\s*$/, /^\$\s*$/, /^<<RESPONSE_END>>$/];
        return patterns.some(p => p.test(line));
    }

    resetSilenceTimer() {
        if (this.silenceTimer) clearTimeout(this.silenceTimer);
        this.silenceTimer = setTimeout(() => {
            if (this.isProcessing) this.finishResponse();
        }, this.silenceTimeout);
    }

    finishResponse() {
        if (this.silenceTimer) {
            clearTimeout(this.silenceTimer);
            this.silenceTimer = null;
        }
        if (this.isProcessing && this.currentCommandId) {
            this.emit('response_end', {
                commandId: this.currentCommandId,
                fullText: this.responseBuffer
            });
        }
        this.isProcessing = false;
        this.currentCommandId = null;
        this.responseBuffer = '';
    }

    async cancel() {
        if (this.process && this.isProcessing) {
            this.process.kill('SIGINT');
            this.finishResponse();
        }
    }

    getStatus() {
        return {
            running: this.process !== null && !this.process.killed,
            ready: this.isReady,
            processing: this.isProcessing,
            currentAgent: { id: this.agent.id, name: this.agent.name }
        };
    }

    async stop() {
        if (this.silenceTimer) clearTimeout(this.silenceTimer);
        if (this.process) {
            this.process.kill();
            this.process = null;
        }
        this.isReady = false;
        this.isProcessing = false;
    }
}
