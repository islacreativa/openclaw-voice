import { existsSync, readFileSync, writeFileSync, copyFileSync, mkdirSync, readdirSync, statSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { createHash, randomBytes } from 'crypto';
import { logger } from '../utils/logger.js';
import { logBus } from '../utils/log-bus.js';
import { getSystemStatus } from '../utils/system-monitor.js';

const SENSITIVE_ACTIONS = new Set([
    'install_mcp',
    'uninstall_mcp',
    'regenerate_token',
    'restore_config',
    'set_env_key'
]);

const KEY_PATTERNS = /^(.*_key|.*_token|.*_secret|password|api_key|api_token)$/i;

export class ConfigHandler {
    constructor({ bridge, config, sessionManager, server, relayStartedAt }) {
        this.bridge = bridge;
        this.config = config;
        this.sessionManager = sessionManager;
        this.server = server;
        this.relayStartedAt = relayStartedAt || Date.now();
        this.messagesProcessed = 0;
        this.logSubscribers = new Map();

        logBus.on('entry', (entry) => this.broadcastLogEntry(entry));
    }

    async handleConfigMessage(ws, msg) {
        this.messagesProcessed++;
        try {
            switch (msg.type) {
                case 'config_get': return await this.handleGet(ws, msg);
                case 'config_set': return await this.handleSet(ws, msg);
                case 'config_action': return await this.handleAction(ws, msg);
                case 'logs_subscribe': return this.handleLogsSubscribe(ws, msg);
                case 'logs_unsubscribe': return this.handleLogsUnsubscribe(ws, msg);
            }
        } catch (err) {
            logger.error(`config-handler: ${err.message}`);
            this.send(ws, {
                type: 'config_result',
                request_id: msg.id,
                payload: { success: false, message: err.message }
            });
        }
    }

    // MARK: - Get

    async handleGet(ws, msg) {
        const { section } = msg.payload || {};
        let data;
        switch (section) {
            case 'openclaw': data = await this.getOpenClawConfig(); break;
            case 'mcps':     data = await this.getMCPsConfig(); break;
            case 'relay':    data = this.getRelayConfig(); break;
            case 'voice':    data = this.getVoiceConfig(); break;
            case 'system':   data = await this.getSystemSection(); break;
            case 'security': data = this.getSecurityConfig(); break;
            default:
                throw new Error(`Unknown section: ${section}`);
        }
        this.send(ws, {
            type: 'config_data',
            request_id: msg.id,
            payload: { section, data }
        });
    }

    async getOpenClawConfig() {
        const agent = this.config.getCurrentAgent();
        const fileConfig = await this.readOpenClawFileConfig();
        return {
            agent: agent ? {
                id: agent.id,
                name: agent.name,
                command: agent.command,
                args: agent.args || [],
                workdir: agent.workdir || homedir(),
                description: agent.description || ''
            } : null,
            available_agents: this.config.listAgents(),
            current_agent_id: this.config.currentAgentId,
            file_config: fileConfig,
            file_config_path: fileConfig?._path || null,
            env: maskEnv(agent?.env || {})
        };
    }

    async readOpenClawFileConfig() {
        const candidates = [
            join(homedir(), '.openclaw', 'config.json'),
            join(homedir(), '.config', 'openclaw', 'config.json'),
            join(homedir(), '.openclaw.json')
        ];
        for (const path of candidates) {
            if (existsSync(path)) {
                try {
                    const raw = JSON.parse(readFileSync(path, 'utf8'));
                    return { ...maskObject(raw), _path: path };
                } catch (err) {
                    return { _path: path, _error: err.message };
                }
            }
        }
        return null;
    }

    async getMCPsConfig() {
        const candidates = [
            join(homedir(), '.openclaw', 'mcps.json'),
            join(homedir(), '.openclaw', 'mcp-servers.json'),
            join(homedir(), '.config', 'openclaw', 'mcps.json')
        ];
        for (const path of candidates) {
            if (existsSync(path)) {
                try {
                    const raw = JSON.parse(readFileSync(path, 'utf8'));
                    const installed = normalizeMCPList(raw);
                    return { installed, _path: path };
                } catch (err) {
                    return { installed: [], error: err.message, _path: path };
                }
            }
        }
        return { installed: [], _path: null };
    }

    getRelayConfig() {
        return {
            port: this.config.port,
            heartbeat_interval_ms: this.config.heartbeatInterval,
            command_timeout_ms: this.config.commandTimeout,
            local_url: this.config.getConnectionURL(),
            tailscale_url: this.config.getTailscaleIP()
                ? `wss://${this.config.getTailscaleIP()}:${this.config.port}/ws`
                : null,
            elevenlabs_api_key_set: !!this.config.elevenLabsApiKey,
            elevenlabs_api_key_masked: maskValue(this.config.elevenLabsApiKey || ''),
            certs_path: this.config.certsPath,
            auth_token_masked: maskValue(this.config.authToken || '')
        };
    }

    getVoiceConfig() {
        return {
            elevenlabs_api_key_set: !!this.config.elevenLabsApiKey,
            elevenlabs_api_key_masked: maskValue(this.config.elevenLabsApiKey || '')
        };
    }

    async getSystemSection() {
        return getSystemStatus({
            bridge: this.bridge,
            config: this.config,
            relayStartedAt: this.relayStartedAt,
            messagesProcessed: this.messagesProcessed,
            connections: this.server?.clients?.size || 0
        });
    }

    getSecurityConfig() {
        return {
            pin_set: !!this.config.securityPinHash
        };
    }

    // MARK: - Set

    async handleSet(ws, msg) {
        const { section, key, value } = msg.payload || {};
        let result;
        switch (section) {
            case 'openclaw': result = await this.setOpenClawValue(key, value, msg); break;
            case 'relay':    result = await this.setRelayValue(key, value); break;
            case 'voice':    result = await this.setVoiceValue(key, value); break;
            default:
                throw new Error(`Section not writable: ${section}`);
        }
        this.send(ws, {
            type: 'config_result',
            request_id: msg.id,
            payload: result
        });
    }

    async setOpenClawValue(key, value, msg) {
        const agent = this.config.getCurrentAgent();
        if (!agent) return { success: false, message: 'No active agent' };
        const allowedAgentKeys = ['command', 'workdir', 'args', 'description'];
        if (allowedAgentKeys.includes(key)) {
            this.config.updateAgent(agent.id, { [key]: value });
            return { success: true, message: `Updated ${key}`, requires_restart: true };
        }
        if (key && key.startsWith('env.')) {
            // Sensitive — require PIN
            const verify = this.requirePin(msg);
            if (!verify.ok) return verify.result;
            const envKey = key.slice(4);
            const newEnv = { ...(agent.env || {}), [envKey]: value };
            this.config.updateAgent(agent.id, { env: newEnv });
            return { success: true, message: `Updated env ${envKey}`, requires_restart: true };
        }
        return { success: false, message: `Unknown key: ${key}` };
    }

    async setRelayValue(key, value) {
        const writable = ['port', 'heartbeatInterval', 'commandTimeout'];
        if (!writable.includes(key)) return { success: false, message: `Key not writable: ${key}` };
        this.config[key] = value;
        this.config.save();
        return { success: true, message: `Updated ${key}`, requires_restart: key === 'port' };
    }

    async setVoiceValue(key, value) {
        if (key === 'elevenlabs_api_key') {
            this.config.elevenLabsApiKey = value || '';
            this.config.save();
            return { success: true, message: 'ElevenLabs API key updated' };
        }
        return { success: false, message: `Unknown key: ${key}` };
    }

    // MARK: - Action

    async handleAction(ws, msg) {
        const payload = msg.payload || {};
        const { action } = payload;

        if (SENSITIVE_ACTIONS.has(action) || action === 'change_pin' || action === 'clear_pin') {
            const verify = this.requirePin(msg);
            if (!verify.ok) {
                return this.send(ws, {
                    type: 'config_result',
                    request_id: msg.id,
                    payload: verify.result
                });
            }
        }

        let result;
        switch (action) {
            case 'restart_openclaw':
                await this.bridge.stop();
                await this.bridge.start();
                result = { success: true, message: 'OpenClaw reiniciado' };
                break;

            case 'restart_relay':
                result = { success: true, message: 'Reiniciando relay…' };
                this.send(ws, { type: 'config_result', request_id: msg.id, payload: result });
                setTimeout(() => process.exit(0), 250);
                return;

            case 'switch_agent':
                if (!payload.agent_id) {
                    result = { success: false, message: 'Falta agent_id' };
                } else {
                    try {
                        const a = await this.bridge.switchAgent(payload.agent_id);
                        result = { success: true, message: `Cambiado a ${a.name}` };
                    } catch (e) {
                        result = { success: false, message: e.message };
                    }
                }
                break;

            case 'regenerate_token':
                this.config.authToken = randomBytes(32).toString('hex');
                this.config.save();
                result = {
                    success: true,
                    message: 'Token regenerado — vuelve a emparejar la app',
                    new_token_masked: maskValue(this.config.authToken)
                };
                break;

            case 'backup_config':
                result = this.backupConfig();
                break;

            case 'restore_config':
                result = this.restoreConfig(payload.backup_id);
                break;

            case 'list_backups':
                result = { success: true, message: 'OK', backups: this.listBackups() };
                break;

            case 'clear_logs':
                logBus.clear();
                result = { success: true, message: 'Logs limpiados' };
                break;

            case 'set_pin':
                result = this.setPin(payload);
                break;

            case 'change_pin':
                result = this.changePin(payload);
                break;

            case 'clear_pin':
                this.config.securityPinHash = null;
                this.config.save();
                result = { success: true, message: 'PIN eliminado' };
                break;

            case 'verify_pin':
                result = { success: this.verifyPin(payload.security_pin), message: 'PIN verificado' };
                break;

            case 'enable_mcp':
            case 'disable_mcp':
            case 'install_mcp':
            case 'uninstall_mcp':
            case 'test_mcp':
                result = { success: false, message: `Acción '${action}' aún no implementada en este relay (requiere CLI de OpenClaw para gestionar MCPs)` };
                break;

            default:
                result = { success: false, message: `Acción desconocida: ${action}` };
        }

        this.send(ws, {
            type: 'config_result',
            request_id: msg.id,
            payload: result
        });
    }

    // MARK: - PIN

    requirePin(msg) {
        if (!this.config.securityPinHash) {
            return { ok: true };
        }
        const pin = msg.payload?.security_pin;
        if (!pin || !this.verifyPin(pin)) {
            return {
                ok: false,
                result: { success: false, message: 'PIN requerido o incorrecto', requires_pin: true }
            };
        }
        return { ok: true };
    }

    verifyPin(pin) {
        if (!pin) return false;
        const hash = hashPin(pin);
        return hash === this.config.securityPinHash;
    }

    setPin(payload) {
        if (this.config.securityPinHash) {
            return { success: false, message: 'PIN ya configurado — usa change_pin' };
        }
        const newPin = payload.new_pin;
        if (!newPin || !/^\d{4,6}$/.test(newPin)) {
            return { success: false, message: 'PIN debe ser 4-6 dígitos' };
        }
        this.config.securityPinHash = hashPin(newPin);
        this.config.save();
        return { success: true, message: 'PIN configurado' };
    }

    changePin(payload) {
        const newPin = payload.new_pin;
        if (!newPin || !/^\d{4,6}$/.test(newPin)) {
            return { success: false, message: 'PIN debe ser 4-6 dígitos' };
        }
        this.config.securityPinHash = hashPin(newPin);
        this.config.save();
        return { success: true, message: 'PIN actualizado' };
    }

    // MARK: - Backups

    backupConfig() {
        const dir = join(this.config.configDir, 'backups');
        if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
        const stamp = new Date().toISOString().replace(/[:.]/g, '-');
        const id = `config-${stamp}`;
        const dest = join(dir, `${id}.json`);
        const src = join(this.config.configDir, 'config.json');
        if (!existsSync(src)) return { success: false, message: 'config.json no encontrado' };
        copyFileSync(src, dest);
        return { success: true, message: `Backup creado: ${id}`, backup_id: id, path: dest };
    }

    listBackups() {
        const dir = join(this.config.configDir, 'backups');
        if (!existsSync(dir)) return [];
        return readdirSync(dir)
            .filter((f) => f.endsWith('.json'))
            .map((f) => {
                const full = join(dir, f);
                const st = statSync(full);
                return {
                    id: f.replace(/\.json$/, ''),
                    created_at: st.mtime.toISOString(),
                    size_bytes: st.size
                };
            })
            .sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
    }

    restoreConfig(backupId) {
        if (!backupId) return { success: false, message: 'Falta backup_id' };
        const src = join(this.config.configDir, 'backups', `${backupId}.json`);
        if (!existsSync(src)) return { success: false, message: 'Backup no encontrado' };
        const dest = join(this.config.configDir, 'config.json');
        copyFileSync(src, dest);
        return { success: true, message: 'Backup restaurado — reinicia el relay para aplicar' };
    }

    // MARK: - Logs

    handleLogsSubscribe(ws, msg) {
        const { source = null, level = 'info', lines = 100 } = msg.payload || {};
        this.logSubscribers.set(ws, { source, level });
        const recent = logBus.recent({ source, level, lines });
        for (const entry of recent) {
            this.send(ws, { type: 'log_entry', payload: entry });
        }
        this.send(ws, {
            type: 'config_result',
            request_id: msg.id,
            payload: { success: true, message: `Suscrito (${recent.length} líneas históricas)` }
        });
    }

    handleLogsUnsubscribe(ws, msg) {
        this.logSubscribers.delete(ws);
        this.send(ws, {
            type: 'config_result',
            request_id: msg.id,
            payload: { success: true, message: 'Desuscrito' }
        });
    }

    broadcastLogEntry(entry) {
        for (const [ws, filter] of this.logSubscribers) {
            if (ws.readyState !== ws.OPEN) {
                this.logSubscribers.delete(ws);
                continue;
            }
            if (filter.source && entry.source !== filter.source) continue;
            if (filter.level && !levelMatches(entry.level, filter.level)) continue;
            this.send(ws, { type: 'log_entry', payload: entry });
        }
    }

    send(ws, obj) {
        if (ws.readyState !== ws.OPEN) return;
        ws.send(JSON.stringify(obj));
    }
}

function hashPin(pin) {
    return createHash('sha256').update(`openclaw-relay:${pin}`).digest('hex');
}

function maskValue(v) {
    if (!v || typeof v !== 'string') return '';
    if (v.length <= 8) return '****';
    return `${v.slice(0, 4)}…${v.slice(-4)}`;
}

function maskEnv(env) {
    const out = {};
    for (const [k, v] of Object.entries(env)) {
        out[k] = KEY_PATTERNS.test(k) ? maskValue(String(v)) : v;
    }
    return out;
}

function maskObject(obj) {
    if (Array.isArray(obj)) return obj.map(maskObject);
    if (obj && typeof obj === 'object') {
        const out = {};
        for (const [k, v] of Object.entries(obj)) {
            if (KEY_PATTERNS.test(k) && typeof v === 'string') {
                out[k] = maskValue(v);
            } else {
                out[k] = maskObject(v);
            }
        }
        return out;
    }
    return obj;
}

function normalizeMCPList(raw) {
    const items = Array.isArray(raw) ? raw : (raw.mcps || raw.installed || []);
    return items.map((item) => ({
        id: item.id || item.name || 'unknown',
        name: item.name || item.id || 'Unknown',
        status: item.status || (item.enabled === false ? 'stopped' : 'unknown'),
        version: item.version || null,
        tools_count: item.tools_count || item.toolsCount || null,
        last_used: item.last_used || item.lastUsed || null,
        config: item.config ? maskObject(item.config) : null
    }));
}

function levelMatches(entryLevel, filterLevel) {
    const order = ['debug', 'info', 'warn', 'error'];
    return order.indexOf(entryLevel) >= order.indexOf(filterLevel);
}
