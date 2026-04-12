import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import readline from 'readline';
import { logger } from '../utils/logger.js';

/**
 * AgentBridge: manages a single AI agent process (OpenClaw, NemoClaw, etc.)
 * with stdin/stdout streaming. Supports switching the active agent at runtime.
 */
export class AgentBridge extends EventEmitter {
    constructor(config) {
        super();
        this.config = config;
        this.process = null;
        this.currentAgent = null;
        this.isReady = false;
        this.isProcessing = false;
        this.currentCommandId = null;
        this.responseBuffer = '';
        this.silenceTimer = null;
        this.chunkIndex = 0;
        this.silenceTimeout = 2000;
    }

    async start() {
        const agent = this.config.getCurrentAgent();
        if (!agent) {
            logger.error('No agent configured');
            return;
        }
        await this.startAgent(agent);
    }

    async startAgent(agent) {
        this.currentAgent = agent;
        logger.info(`Starting agent '${agent.name}': ${agent.command} ${(agent.args || []).join(' ')}`);

        try {
            this.process = spawn(agent.command, agent.args || [], {
                cwd: agent.workdir,
                env: { ...process.env, ...(agent.env || {}) },
                stdio: ['pipe', 'pipe', 'pipe']
            });
        } catch (err) {
            logger.error(`Failed to spawn agent '${agent.name}': ${err.message}`);
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
                logger.debug(`[${agent.name}] stderr: ${text}`);
            }
        });

        this.process.on('close', (code) => {
            logger.warn(`Agent '${agent.name}' exited with code ${code}`);
            this.isReady = false;
            this.isProcessing = false;
            this.emit('closed', code);

            // Only auto-restart if still the current agent
            if (code !== 0 && code !== null && this.currentAgent?.id === agent.id) {
                logger.info(`Auto-restarting '${agent.name}' in 2s...`);
                setTimeout(() => {
                    if (this.currentAgent?.id === agent.id) {
                        this.startAgent(agent);
                    }
                }, 2000);
            }
        });

        this.process.on('error', (err) => {
            logger.error(`Agent '${agent.name}' process error: ${err.message}`);
            this.isReady = false;
        });

        this.isReady = true;
        this.emit('ready', { agent: agent.id });
        logger.info(`Agent '${agent.name}' ready`);
    }

    /**
     * Switch to a different agent. Gracefully stops current and starts new.
     */
    async switchAgent(agentId) {
        if (this.isProcessing) {
            throw new Error('Cannot switch agent while a command is being processed');
        }

        const newAgent = this.config.setCurrentAgent(agentId);
        logger.info(`Switching to agent: ${newAgent.name}`);

        // Stop current process
        if (this.process) {
            this.process.kill();
            await new Promise(resolve => {
                this.process.once('close', resolve);
                setTimeout(resolve, 1000); // max wait 1s
            });
        }

        this.process = null;
        this.isReady = false;

        // Start new agent
        await this.startAgent(newAgent);
        return newAgent;
    }

    async sendCommand(text, commandId) {
        if (!this.isReady) {
            throw new Error(`Agent '${this.currentAgent?.name || 'unknown'}' not ready`);
        }
        if (this.isProcessing) {
            throw new Error('Agent is busy');
        }

        this.isProcessing = true;
        this.currentCommandId = commandId;
        this.responseBuffer = '';
        this.chunkIndex = 0;

        logger.info(`[${this.currentAgent.name}] Command [${commandId}]: ${text.substring(0, 80)}...`);

        this.process.stdin.write(text + '\n');
        this.emit('response_start', { commandId, agent: this.currentAgent.id });
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
        const promptPatterns = [
            /^>\s*$/,
            /^openclaw>\s*$/i,
            /^nemoclaw>\s*$/i,
            /^claude>\s*$/i,
            /^\$\s*$/,
            /^<<RESPONSE_END>>$/
        ];
        return promptPatterns.some(p => p.test(line));
    }

    resetSilenceTimer() {
        if (this.silenceTimer) clearTimeout(this.silenceTimer);
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
            processing: this.isProcessing,
            currentAgent: this.currentAgent ? {
                id: this.currentAgent.id,
                name: this.currentAgent.name
            } : null
        };
    }

    async stop() {
        if (this.silenceTimer) clearTimeout(this.silenceTimer);
        if (this.process) {
            this.process.kill();
            this.process = null;
            this.isReady = false;
            this.isProcessing = false;
        }
    }
}

// Alias for backwards compatibility
export const OpenClawBridge = AgentBridge;
