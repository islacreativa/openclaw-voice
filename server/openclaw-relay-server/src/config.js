import { randomBytes } from 'crypto';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { homedir, networkInterfaces } from 'os';

// Built-in agent presets — users can add/edit more in config.json
export const DEFAULT_AGENTS = [
    {
        id: 'openclaw',
        name: 'OpenClaw',
        command: 'openclaw',
        args: [],
        workdir: null,
        env: {},
        description: 'OpenClaw AI assistant'
    },
    {
        id: 'nemoclaw',
        name: 'NemoClaw',
        command: 'nemoclaw',
        args: [],
        workdir: null,
        env: {},
        description: 'NemoClaw AI assistant'
    }
];

export class Config {
    constructor() {
        this.configDir = join(homedir(), '.openclaw-relay');
        const configPath = join(this.configDir, 'config.json');

        if (existsSync(configPath)) {
            const saved = JSON.parse(readFileSync(configPath, 'utf8'));
            Object.assign(this, saved);
            // Migrate legacy single-agent config
            this.migrateLegacy();
        } else {
            this.port = parseInt(process.env.OPENCLAW_RELAY_PORT || '8765', 10);
            this.authToken = randomBytes(32).toString('hex');
            this.certsPath = join(this.configDir, 'certs');
            this.heartbeatInterval = 15000;
            this.commandTimeout = 60000;

            // Multi-agent configuration
            this.agents = DEFAULT_AGENTS.map(a => ({ ...a }));
            this.currentAgentId = 'openclaw';

            // Optional: ElevenLabs API key (included in QR so the app can
            // auto-configure voice synthesis on first pair). Can be set via
            // env var or edited in ~/.openclaw-relay/config.json afterwards.
            this.elevenLabsApiKey = process.env.ELEVENLABS_API_KEY || '';

            // Apply env overrides for the default agent
            const envCommand = process.env.OPENCLAW_COMMAND;
            const envWorkdir = process.env.OPENCLAW_WORKDIR || homedir();
            if (envCommand) {
                const defaultAgent = this.agents.find(a => a.id === 'openclaw');
                if (defaultAgent) {
                    defaultAgent.command = envCommand;
                    defaultAgent.workdir = envWorkdir;
                }
            }
            for (const agent of this.agents) {
                if (!agent.workdir) agent.workdir = homedir();
            }

            if (!existsSync(this.configDir)) {
                mkdirSync(this.configDir, { recursive: true });
            }
            this.save();
        }
    }

    migrateLegacy() {
        if (this.openclawCommand && !this.agents) {
            this.agents = [{
                id: 'openclaw',
                name: 'OpenClaw',
                command: this.openclawCommand,
                args: this.openclawArgs || [],
                workdir: this.openclawWorkdir || homedir(),
                env: this.openclawEnv || {},
                description: 'OpenClaw AI assistant'
            }];
            // Add NemoClaw as available
            this.agents.push({
                id: 'nemoclaw',
                name: 'NemoClaw',
                command: 'nemoclaw',
                args: [],
                workdir: homedir(),
                env: {},
                description: 'NemoClaw AI assistant'
            });
            this.currentAgentId = 'openclaw';
            delete this.openclawCommand;
            delete this.openclawArgs;
            delete this.openclawWorkdir;
            delete this.openclawEnv;
            this.save();
        }
    }

    save() {
        const configPath = join(this.configDir, 'config.json');
        const data = {
            port: this.port,
            authToken: this.authToken,
            certsPath: this.certsPath,
            heartbeatInterval: this.heartbeatInterval,
            commandTimeout: this.commandTimeout,
            agents: this.agents,
            currentAgentId: this.currentAgentId,
            elevenLabsApiKey: this.elevenLabsApiKey || ''
        };
        writeFileSync(configPath, JSON.stringify(data, null, 2));
    }

    // MARK: - Agent management

    getCurrentAgent() {
        return this.agents.find(a => a.id === this.currentAgentId) || this.agents[0];
    }

    setCurrentAgent(agentId) {
        const agent = this.agents.find(a => a.id === agentId);
        if (!agent) {
            throw new Error(`Agent not found: ${agentId}`);
        }
        this.currentAgentId = agentId;
        this.save();
        return agent;
    }

    listAgents() {
        return this.agents.map(a => ({
            id: a.id,
            name: a.name,
            description: a.description,
            command: a.command,
            isCurrent: a.id === this.currentAgentId
        }));
    }

    addAgent(agent) {
        if (this.agents.find(a => a.id === agent.id)) {
            throw new Error(`Agent already exists: ${agent.id}`);
        }
        this.agents.push({
            id: agent.id,
            name: agent.name,
            command: agent.command,
            args: agent.args || [],
            workdir: agent.workdir || homedir(),
            env: agent.env || {},
            description: agent.description || ''
        });
        this.save();
    }

    removeAgent(agentId) {
        const idx = this.agents.findIndex(a => a.id === agentId);
        if (idx < 0) throw new Error(`Agent not found: ${agentId}`);
        if (this.currentAgentId === agentId) {
            throw new Error('Cannot remove the current agent. Switch to another agent first.');
        }
        this.agents.splice(idx, 1);
        this.save();
    }

    updateAgent(agentId, updates) {
        const agent = this.agents.find(a => a.id === agentId);
        if (!agent) throw new Error(`Agent not found: ${agentId}`);
        Object.assign(agent, updates);
        this.save();
        return agent;
    }

    // MARK: - Network

    getLocalIP() {
        const ifaces = networkInterfaces();
        for (const name of Object.keys(ifaces)) {
            for (const iface of ifaces[name]) {
                if (iface.family === 'IPv4' && !iface.internal) {
                    return iface.address;
                }
            }
        }
        return 'localhost';
    }

    getTailscaleIP() {
        const ifaces = networkInterfaces();
        for (const [name, addrs] of Object.entries(ifaces)) {
            if (name.startsWith('utun') || name === 'tailscale0') {
                const v4 = addrs.find(a => a.family === 'IPv4');
                if (v4 && v4.address.startsWith('100.')) return v4.address;
            }
        }
        return null;
    }

    getConnectionURL() {
        return `wss://${this.getLocalIP()}:${this.port}/ws`;
    }

    getQRData() {
        const data = {
            url: this.getConnectionURL(),
            token: this.authToken,
            name: `OpenClaw Voice Relay`
        };
        const tailscale = this.getTailscaleIP();
        if (tailscale) {
            data.tailscale_url = `wss://${tailscale}:${this.port}/ws`;
        }
        if (this.elevenLabsApiKey) {
            data.elevenlabs_api_key = this.elevenLabsApiKey;
        }
        return data;
    }
}
