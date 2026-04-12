import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import { logger } from '../../utils/logger.js';

/**
 * OpenClaw adapter: invokes `openclaw agent --message "..." --json` per
 * command. Maintains a default session across commands unless a specific
 * session-id is provided.
 *
 * Config:
 *   command: 'openclaw' (or full path)
 *   args: extra CLI args (e.g. ['--profile', 'dev'])
 *   workdir: working directory
 *   env: extra environment vars
 *   sessionId: optional — reuse a specific session (otherwise auto-derived)
 */
export class OpenClawAdapter extends EventEmitter {
    constructor(agent) {
        super();
        this.agent = agent;
        this.isReady = false;
        this.isProcessing = false;
        this.currentCommandId = null;
        this.currentProcess = null;
        this.sessionId = agent.sessionId || null;
    }

    async start() {
        // Verify the command exists
        try {
            await this.runOnce(['--version']);
            this.isReady = true;
            this.emit('ready', { agent: this.agent.id });
            logger.info(`OpenClaw adapter ready (command: ${this.agent.command})`);
        } catch (err) {
            logger.error(`OpenClaw adapter failed to start: ${err.message}`);
            this.isReady = false;
            this.emit('error', { message: err.message });
        }
    }

    async stop() {
        if (this.currentProcess) {
            this.currentProcess.kill();
            this.currentProcess = null;
        }
        this.isReady = false;
        this.isProcessing = false;
    }

    async sendCommand(text, commandId) {
        if (!this.isReady) throw new Error('OpenClaw adapter not ready');
        if (this.isProcessing) throw new Error('OpenClaw is busy');

        this.isProcessing = true;
        this.currentCommandId = commandId;

        // Ensure we have a session to use
        await this.ensureSession();

        const args = [
            'agent',
            '--session-id', this.sessionId,
            '--message', text,
            '--json'
        ];

        logger.info(`[OpenClaw] Running: openclaw ${args.slice(0, 4).join(' ')} "${text.substring(0, 50)}..."`);
        this.emit('response_start', { commandId });

        try {
            const jsonOutput = await this.runOnce(args);
            const response = JSON.parse(jsonOutput);

            const payloads = response?.result?.payloads || [];
            const fullText = payloads.map(p => p.text).filter(Boolean).join('\n');

            if (!fullText) {
                logger.warn('[OpenClaw] Empty response');
                this.emit('response_end', { commandId, fullText: '(empty response)' });
            } else {
                // Emit as chunks so the iOS client gets streaming-like behavior.
                // Split into sentences for a more natural streaming experience.
                const sentences = splitIntoSentences(fullText);
                for (let i = 0; i < sentences.length; i++) {
                    this.emit('response_chunk', {
                        commandId,
                        text: sentences[i],
                        chunkIndex: i
                    });
                }
                this.emit('response_end', { commandId, fullText });
            }

            logger.info(`[OpenClaw] Response: ${fullText.length} chars`);
        } catch (err) {
            logger.error(`[OpenClaw] Error: ${err.message}`);
            this.emit('response_error', { commandId, message: err.message });
        } finally {
            this.isProcessing = false;
            this.currentCommandId = null;
            this.currentProcess = null;
        }
    }

    async ensureSession() {
        if (this.sessionId) return;

        // Try to find an existing "main" session
        try {
            const output = await this.runOnce(['sessions', '--json']);
            const data = JSON.parse(output);
            const mainSession = data.sessions?.find(s => s.key === 'agent:main:main') || data.sessions?.[0];
            if (mainSession?.sessionId) {
                this.sessionId = mainSession.sessionId;
                logger.info(`[OpenClaw] Using existing session: ${this.sessionId}`);
                return;
            }
        } catch (err) {
            logger.warn(`[OpenClaw] Could not list sessions: ${err.message}`);
        }

        // Fallback: use --to with a synthetic E.164 to auto-create a session
        this.sessionId = null;  // Will fall back to --to routing
        logger.warn('[OpenClaw] No existing session; commands will fail unless one is created');
    }

    /**
     * Run the openclaw CLI with given args and capture stdout.
     * stderr is logged but not returned.
     */
    runOnce(args) {
        return new Promise((resolve, reject) => {
            const fullArgs = [...(this.agent.args || []), ...args];
            const proc = spawn(this.agent.command, fullArgs, {
                cwd: this.agent.workdir,
                env: { ...process.env, ...(this.agent.env || {}) }
            });

            this.currentProcess = proc;

            let stdout = '';
            let stderr = '';

            proc.stdout.on('data', (data) => {
                stdout += data.toString();
            });

            proc.stderr.on('data', (data) => {
                const text = data.toString();
                stderr += text;
                logger.debug(`[OpenClaw stderr] ${text.trim()}`);
            });

            proc.on('close', (code) => {
                this.currentProcess = null;
                if (code === 0) {
                    resolve(stdout);
                } else {
                    reject(new Error(`openclaw exited with code ${code}: ${stderr || stdout}`));
                }
            });

            proc.on('error', (err) => {
                this.currentProcess = null;
                reject(err);
            });
        });
    }

    async cancel() {
        if (this.currentProcess) {
            logger.info('[OpenClaw] Cancelling current command');
            this.currentProcess.kill('SIGINT');
        }
        this.isProcessing = false;
    }

    getStatus() {
        return {
            running: true,
            ready: this.isReady,
            processing: this.isProcessing,
            currentAgent: { id: this.agent.id, name: this.agent.name },
            sessionId: this.sessionId
        };
    }
}

// Split text into sentences for smoother streaming UX.
// Uses a simple regex: splits on sentence-ending punctuation followed by space or EOL.
function splitIntoSentences(text) {
    const parts = text.match(/[^.!?\n]+[.!?\n]?\s*/g) || [text];
    return parts.map(s => s.trim()).filter(Boolean);
}
