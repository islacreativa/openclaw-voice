import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import readline from 'readline';
import { logger } from '../utils/logger.js';

export class OpenClawBridge extends EventEmitter {
    constructor(config) {
        super();
        this.config = config;
        this.process = null;
        this.isReady = false;
        this.isProcessing = false;
        this.currentCommandId = null;
        this.responseBuffer = '';
        this.silenceTimer = null;
        this.chunkIndex = 0;
        // How long of silence before we consider a response complete (ms)
        this.silenceTimeout = 2000;
    }

    async start() {
        logger.info(`Starting OpenClaw: ${this.config.openclawCommand} ${this.config.openclawArgs.join(' ')}`);

        try {
            this.process = spawn(this.config.openclawCommand, this.config.openclawArgs, {
                cwd: this.config.openclawWorkdir,
                env: { ...process.env, ...this.config.openclawEnv },
                stdio: ['pipe', 'pipe', 'pipe']
            });
        } catch (err) {
            logger.error(`Failed to spawn OpenClaw: ${err.message}`);
            this.isReady = false;
            this.emit('error', { message: err.message });
            return;
        }

        const rl = readline.createInterface({
            input: this.process.stdout,
            crlfDelay: Infinity
        });

        rl.on('line', (line) => {
            this.handleOutputLine(line);
        });

        this.process.stderr.on('data', (data) => {
            const text = data.toString().trim();
            if (text) {
                logger.debug(`OpenClaw stderr: ${text}`);
            }
        });

        this.process.on('close', (code) => {
            logger.warn(`OpenClaw process exited with code ${code}`);
            this.isReady = false;
            this.isProcessing = false;
            this.emit('closed', code);

            if (code !== 0 && code !== null) {
                logger.info('Auto-restarting OpenClaw in 2s...');
                setTimeout(() => this.start(), 2000);
            }
        });

        this.process.on('error', (err) => {
            logger.error(`OpenClaw process error: ${err.message}`);
            this.isReady = false;
        });

        this.isReady = true;
        this.emit('ready');
        logger.info('OpenClaw bridge ready');
    }

    async sendCommand(text, commandId) {
        if (!this.isReady) {
            throw new Error('OpenClaw not ready');
        }
        if (this.isProcessing) {
            throw new Error('OpenClaw is busy');
        }

        this.isProcessing = true;
        this.currentCommandId = commandId;
        this.responseBuffer = '';
        this.chunkIndex = 0;

        logger.info(`Sending command [${commandId}]: ${text.substring(0, 80)}...`);

        this.process.stdin.write(text + '\n');
        this.emit('response_start', { commandId });
        this.resetSilenceTimer();
    }

    handleOutputLine(line) {
        const trimmed = line.trim();
        if (!trimmed) return;

        // Check if this looks like a prompt (end of response marker)
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
        // Detect common prompt patterns that indicate end of response
        // Adapt this based on how OpenClaw signals end of output
        const promptPatterns = [
            /^>\s*$/,                    // Just ">"
            /^openclaw>\s*$/i,           // "openclaw>"
            /^claude>\s*$/i,             // "claude>"
            /^\$\s*$/,                   // Just "$"
            /^<<RESPONSE_END>>$/,        // Custom wrapper marker
        ];
        return promptPatterns.some(p => p.test(line));
    }

    resetSilenceTimer() {
        if (this.silenceTimer) {
            clearTimeout(this.silenceTimer);
        }
        this.silenceTimer = setTimeout(() => {
            if (this.isProcessing) {
                logger.debug('Silence timeout — finishing response');
                this.finishResponse();
            }
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
            logger.info(`Response complete [${this.currentCommandId}]: ${this.responseBuffer.length} chars`);
        }

        this.isProcessing = false;
        this.currentCommandId = null;
        this.responseBuffer = '';
    }

    async cancel() {
        if (this.process && this.isProcessing) {
            logger.info('Cancelling current command (SIGINT)');
            this.process.kill('SIGINT');
            this.finishResponse();
        }
    }

    getStatus() {
        return {
            running: this.process !== null && !this.process.killed,
            ready: this.isReady,
            processing: this.isProcessing
        };
    }

    async stop() {
        if (this.silenceTimer) {
            clearTimeout(this.silenceTimer);
        }
        if (this.process) {
            this.process.kill();
            this.process = null;
            this.isReady = false;
            this.isProcessing = false;
        }
    }
}
