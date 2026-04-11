import { randomBytes } from 'crypto';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { homedir, networkInterfaces } from 'os';

export class Config {
    constructor() {
        this.configDir = join(homedir(), '.openclaw-relay');
        const configPath = join(this.configDir, 'config.json');

        if (existsSync(configPath)) {
            const saved = JSON.parse(readFileSync(configPath, 'utf8'));
            Object.assign(this, saved);
        } else {
            this.port = parseInt(process.env.OPENCLAW_RELAY_PORT || '8765', 10);
            this.authToken = randomBytes(32).toString('hex');
            this.certsPath = join(this.configDir, 'certs');
            this.openclawCommand = process.env.OPENCLAW_COMMAND || 'openclaw';
            this.openclawArgs = [];
            this.openclawWorkdir = process.env.OPENCLAW_WORKDIR || homedir();
            this.openclawEnv = {};
            this.heartbeatInterval = 15000;
            this.commandTimeout = 60000;

            if (!existsSync(this.configDir)) {
                mkdirSync(this.configDir, { recursive: true });
            }
            writeFileSync(configPath, JSON.stringify(this, null, 2));
        }
    }

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
            name: `OpenClaw Relay`
        };
        const tailscale = this.getTailscaleIP();
        if (tailscale) {
            data.tailscale_url = `wss://${tailscale}:${this.port}/ws`;
        }
        return data;
    }
}
