import os from 'os';
import { exec } from 'child_process';
import { statfs } from 'fs';

let lastCpuSample = null;

function sampleCpu() {
    const cpus = os.cpus();
    let user = 0, sys = 0, idle = 0, total = 0;
    for (const cpu of cpus) {
        user += cpu.times.user;
        sys += cpu.times.sys;
        idle += cpu.times.idle;
        total += cpu.times.user + cpu.times.nice + cpu.times.sys + cpu.times.idle + cpu.times.irq;
    }
    return { user, sys, idle, total };
}

function cpuUsagePercent() {
    const sample = sampleCpu();
    if (!lastCpuSample) {
        lastCpuSample = sample;
        return null;
    }
    const totalDiff = sample.total - lastCpuSample.total;
    const idleDiff = sample.idle - lastCpuSample.idle;
    lastCpuSample = sample;
    if (totalDiff <= 0) return null;
    return Math.max(0, Math.min(100, ((totalDiff - idleDiff) / totalDiff) * 100));
}

function execAsync(cmd, timeoutMs = 1500) {
    return new Promise((resolve) => {
        exec(cmd, { timeout: timeoutMs }, (err, stdout) => {
            if (err) return resolve(null);
            resolve(stdout.trim());
        });
    });
}

async function getBattery() {
    const out = await execAsync('pmset -g batt');
    if (!out) return null;
    const match = out.match(/(\d+)%;\s*([^;]+);/);
    if (!match) return null;
    return {
        percent: parseInt(match[1], 10),
        charging: /charged|charging|AC Power/i.test(match[2])
    };
}

async function getMacOSVersion() {
    const out = await execAsync('sw_vers -productVersion');
    return out ? `macOS ${out}` : `Darwin ${os.release()}`;
}

function getDiskFreeGB() {
    return new Promise((resolve) => {
        statfs('/', (err, stats) => {
            if (err) return resolve(null);
            const free = stats.bavail * stats.bsize;
            resolve(Number((free / 1e9).toFixed(1)));
        });
    });
}

function getNetwork(config) {
    const ifaces = os.networkInterfaces();
    let localIP = 'localhost';
    for (const name of Object.keys(ifaces)) {
        for (const iface of ifaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal && !iface.address.startsWith('100.')) {
                localIP = iface.address;
                break;
            }
        }
        if (localIP !== 'localhost') break;
    }
    const tailscaleIP = config && typeof config.getTailscaleIP === 'function' ? config.getTailscaleIP() : null;
    return {
        local_ip: localIP,
        tailscale_ip: tailscaleIP,
        tailscale_status: tailscaleIP ? 'connected' : 'not_detected'
    };
}

export async function getSystemStatus({ bridge, config, relayStartedAt, messagesProcessed, connections } = {}) {
    const totalMem = os.totalmem();
    const freeMem = os.freemem();

    const [battery, osVersion, diskFreeGB] = await Promise.all([
        getBattery(),
        getMacOSVersion(),
        getDiskFreeGB()
    ]);

    const cpuPercent = cpuUsagePercent();
    const bridgeStatus = bridge ? bridge.getStatus() : null;

    return {
        mac: {
            hostname: os.hostname(),
            os_version: osVersion,
            cpu_usage: cpuPercent != null ? Number(cpuPercent.toFixed(1)) : null,
            cpu_cores: os.cpus().length,
            memory_used_gb: Number(((totalMem - freeMem) / 1e9).toFixed(1)),
            memory_total_gb: Number((totalMem / 1e9).toFixed(1)),
            disk_free_gb: diskFreeGB,
            battery_percent: battery ? battery.percent : null,
            battery_charging: battery ? battery.charging : null,
            uptime_hours: Number((os.uptime() / 3600).toFixed(1))
        },
        openclaw: {
            status: bridgeStatus?.ready ? 'running' : (bridgeStatus?.running ? 'starting' : 'stopped'),
            processing: !!bridgeStatus?.processing,
            current_agent: bridgeStatus?.currentAgent || null,
            session_id: bridgeStatus?.sessionId || null
        },
        relay: {
            status: 'running',
            connections: connections ?? 0,
            uptime_seconds: relayStartedAt ? Math.round((Date.now() - relayStartedAt) / 1000) : Math.round(process.uptime()),
            messages_processed: messagesProcessed ?? 0,
            memory_mb: Number((process.memoryUsage().rss / 1e6).toFixed(1))
        },
        network: getNetwork(config)
    };
}

// Initialize the CPU sample so first call returns a real number
sampleCpu();
