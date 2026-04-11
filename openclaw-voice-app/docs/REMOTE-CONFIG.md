# Configuración Remota de OpenClaw desde la App

## 1. Visión General

La app iOS incluye un módulo de configuración que permite gestionar y configurar OpenClaw de forma remota desde el iPhone, sin necesidad de estar frente al portátil. Esto incluye:

- Ver y editar la configuración de OpenClaw
- Gestionar MCPs conectados (activar, desactivar, configurar)
- Ver logs y estado del sistema
- Reiniciar OpenClaw
- Gestionar API keys y credenciales
- Configurar el Relay Server
- Ver métricas de uso

## 2. Arquitectura

```
┌──────────────────────────────────────────────┐
│                   iPhone                      │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │         Config Dashboard               │  │
│  │                                        │  │
│  │  ┌──────────┐  ┌───────────────────┐   │  │
│  │  │ OpenClaw │  │ MCP Management    │   │  │
│  │  │ Settings │  │                   │   │  │
│  │  └──────────┘  └───────────────────┘   │  │
│  │  ┌──────────┐  ┌───────────────────┐   │  │
│  │  │ Logs     │  │ System Status     │   │  │
│  │  │ Viewer   │  │                   │   │  │
│  │  └──────────┘  └───────────────────┘   │  │
│  └────────────────────────────────────────┘  │
│                     │                        │
└─────────────────────┼────────────────────────┘
                      │ WebSocket (config channel)
                      ▼
┌──────────────────────────────────────────────┐
│                    Mac                        │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │           Relay Server                 │  │
│  │                                        │  │
│  │  ┌──────────────────────────────────┐  │  │
│  │  │     Config API Module            │  │  │
│  │  │                                  │  │  │
│  │  │  • Read/Write config files       │  │  │
│  │  │  • Manage MCP processes          │  │  │
│  │  │  • Read log files                │  │  │
│  │  │  • Restart services              │  │  │
│  │  │  • System monitoring             │  │  │
│  │  └──────────────────────────────────┘  │  │
│  └────────────────────────────────────────┘  │
│                     │                        │
│              ┌──────┴──────┐                 │
│              │  OpenClaw   │                 │
│              │  + Configs  │                 │
│              └─────────────┘                 │
└──────────────────────────────────────────────┘
```

## 3. Protocolo — Mensajes de Configuración

### 3.1 Cliente → Servidor

#### config_get — Leer configuración
```json
{
  "type": "config_get",
  "id": "uuid",
  "payload": {
    "section": "openclaw",
    "key": null
  }
}
```

Secciones disponibles:
- `openclaw` — Configuración general de OpenClaw
- `mcps` — MCPs instalados y su estado
- `relay` — Configuración del relay server
- `voice` — Configuración de voz del servidor
- `system` — Estado del sistema (CPU, RAM, disco)

#### config_set — Escribir configuración
```json
{
  "type": "config_set",
  "id": "uuid",
  "payload": {
    "section": "openclaw",
    "key": "model",
    "value": "claude-sonnet-4-20250514"
  }
}
```

#### config_action — Ejecutar acción
```json
{
  "type": "config_action",
  "id": "uuid",
  "payload": {
    "action": "restart_openclaw"
  }
}
```

Acciones disponibles:
- `restart_openclaw` — Reiniciar el proceso OpenClaw
- `restart_relay` — Reiniciar el relay server
- `enable_mcp` — Activar un MCP `{ "mcp_id": "..." }`
- `disable_mcp` — Desactivar un MCP `{ "mcp_id": "..." }`
- `install_mcp` — Instalar un nuevo MCP `{ "mcp_url": "..." }`
- `uninstall_mcp` — Desinstalar un MCP `{ "mcp_id": "..." }`
- `test_mcp` — Probar conexión de un MCP `{ "mcp_id": "..." }`
- `clear_logs` — Limpiar logs
- `regenerate_token` — Regenerar token de autenticación
- `backup_config` — Crear backup de la configuración
- `restore_config` — Restaurar configuración desde backup

#### logs_subscribe — Suscribirse a logs en tiempo real
```json
{
  "type": "logs_subscribe",
  "id": "uuid",
  "payload": {
    "source": "openclaw",
    "level": "info",
    "lines": 100
  }
}
```

### 3.2 Servidor → Cliente

#### config_data — Datos de configuración
```json
{
  "type": "config_data",
  "request_id": "uuid",
  "payload": {
    "section": "openclaw",
    "data": {
      "model": "claude-sonnet-4-20250514",
      "max_tokens": 4096,
      "temperature": 0.7,
      "system_prompt": "...",
      "tools_enabled": true,
      "mcps": ["crm-tribucorp", "figma", "slack"],
      "working_directory": "/Users/javier",
      "env_vars": {
        "ANTHROPIC_API_KEY": "sk-ant-...****",
        "ELEVENLABS_API_KEY": "...****"
      }
    }
  }
}
```

#### config_result — Resultado de config_set o config_action
```json
{
  "type": "config_result",
  "request_id": "uuid",
  "payload": {
    "success": true,
    "message": "OpenClaw reiniciado correctamente",
    "requires_restart": false
  }
}
```

#### mcps_list — Lista de MCPs
```json
{
  "type": "config_data",
  "request_id": "uuid",
  "payload": {
    "section": "mcps",
    "data": {
      "installed": [
        {
          "id": "crm-tribucorp",
          "name": "CRM TribuCorp",
          "status": "running",
          "version": "1.0.0",
          "tools_count": 45,
          "last_used": "2026-04-11T09:30:00Z",
          "config": {
            "api_url": "https://crm.tribucorp.com/api",
            "api_key": "...****"
          }
        },
        {
          "id": "figma",
          "name": "Figma",
          "status": "stopped",
          "version": "2.1.0",
          "tools_count": 12,
          "last_used": "2026-04-10T15:00:00Z"
        }
      ],
      "available": [
        {
          "id": "slack",
          "name": "Slack",
          "description": "Connect to Slack workspaces",
          "install_url": "..."
        }
      ]
    }
  }
}
```

#### log_entry — Entrada de log en tiempo real
```json
{
  "type": "log_entry",
  "payload": {
    "source": "openclaw",
    "level": "info",
    "message": "Tool call: crm_opportunities_search",
    "timestamp": "2026-04-11T10:30:15Z",
    "metadata": {
      "tool": "crm_opportunities_search",
      "duration_ms": 450
    }
  }
}
```

#### system_status — Estado del sistema
```json
{
  "type": "config_data",
  "request_id": "uuid",
  "payload": {
    "section": "system",
    "data": {
      "mac": {
        "hostname": "MacBook-Pro-Javier",
        "os_version": "macOS 15.2",
        "cpu_usage": 23.5,
        "memory_used_gb": 12.4,
        "memory_total_gb": 36,
        "disk_free_gb": 234,
        "battery_percent": 78,
        "battery_charging": true,
        "uptime_hours": 48
      },
      "openclaw": {
        "status": "running",
        "pid": 12345,
        "memory_mb": 256,
        "uptime_seconds": 3600,
        "commands_processed": 42,
        "active_mcps": 3,
        "last_error": null
      },
      "relay": {
        "status": "running",
        "connections": 1,
        "uptime_seconds": 7200,
        "messages_processed": 156
      },
      "network": {
        "local_ip": "192.168.1.50",
        "tailscale_ip": "100.64.0.1",
        "tailscale_status": "connected"
      }
    }
  }
}
```

## 4. Vistas en la App iOS

### 4.1 Estructura de navegación

```
Settings Tab
├── Conexión
│   ├── Estado de conexión (indicador visual)
│   ├── URL del servidor
│   ├── Reconectar
│   └── Cambiar servidor (QR)
│
├── OpenClaw
│   ├── Estado (running/stopped/error)
│   ├── Modelo activo
│   ├── System prompt (editor)
│   ├── Temperatura / Max tokens
│   ├── Reiniciar OpenClaw
│   └── Ver configuración completa
│
├── MCPs
│   ├── Lista de MCPs instalados
│   │   ├── Estado (running/stopped)
│   │   ├── Toggle activar/desactivar
│   │   ├── Configuración del MCP
│   │   └── Probar conexión
│   ├── Instalar nuevo MCP
│   └── MCPs disponibles (marketplace)
│
├── Voz
│   ├── Voz de ElevenLabs (selector)
│   ├── Velocidad / Estabilidad
│   ├── Preview de voz
│   ├── Idioma STT
│   └── Modo de escucha (push-to-talk / continuo)
│
├── Logs
│   ├── Logs en tiempo real
│   ├── Filtrar por nivel (debug/info/warn/error)
│   ├── Filtrar por fuente (openclaw/relay/mcp)
│   └── Limpiar logs
│
├── Sistema
│   ├── Estado del Mac (CPU, RAM, batería)
│   ├── Estado de red (local IP, Tailscale)
│   ├── Métricas de uso
│   └── Backup / Restaurar configuración
│
└── Relay Server
    ├── Puerto
    ├── Regenerar token
    ├── Certificado TLS
    └── Reiniciar relay
```

### 4.2 Nuevos archivos Swift necesarios

```
Views/
├── Settings/
│   ├── SettingsView.swift                    ← Ya existente, ampliar
│   ├── OpenClawConfigView.swift              ← NUEVO: config de OpenClaw
│   ├── MCPManagementView.swift               ← NUEVO: gestión de MCPs
│   ├── MCPDetailView.swift                   ← NUEVO: detalle de un MCP
│   ├── LogViewerView.swift                   ← NUEVO: visor de logs
│   ├── SystemStatusView.swift                ← NUEVO: estado del sistema
│   └── RelayConfigView.swift                 ← NUEVO: config del relay

ViewModels/
│   ├── ConfigViewModel.swift                 ← NUEVO: lógica de config
│   ├── MCPViewModel.swift                    ← NUEVO: lógica de MCPs
│   └── LogViewModel.swift                    ← NUEVO: lógica de logs

Services/
│   └── Config/
│       ├── RemoteConfigService.swift         ← NUEVO: comunicación de config
│       └── SystemMonitorService.swift        ← NUEVO: monitor del sistema
```

### 4.3 Ejemplo de Vista: MCPManagementView

```swift
import SwiftUI

struct MCPManagementView: View {
    @Environment(ConfigViewModel.self) var config
    
    var body: some View {
        List {
            Section("MCPs Activos") {
                ForEach(config.installedMCPs.filter { $0.status == .running }) { mcp in
                    MCPRow(mcp: mcp)
                }
            }
            
            Section("MCPs Instalados (Inactivos)") {
                ForEach(config.installedMCPs.filter { $0.status == .stopped }) { mcp in
                    MCPRow(mcp: mcp)
                }
            }
            
            Section {
                Button("Instalar nuevo MCP") {
                    config.showMCPMarketplace = true
                }
            }
        }
        .navigationTitle("MCPs")
        .refreshable {
            await config.refreshMCPs()
        }
    }
}

struct MCPRow: View {
    let mcp: MCPInfo
    @Environment(ConfigViewModel.self) var config
    
    var body: some View {
        NavigationLink(destination: MCPDetailView(mcp: mcp)) {
            HStack {
                Circle()
                    .fill(mcp.status == .running ? .green : .gray)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading) {
                    Text(mcp.name)
                        .font(.headline)
                    Text("\(mcp.toolsCount) herramientas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { mcp.status == .running },
                    set: { newValue in
                        Task {
                            if newValue {
                                await config.enableMCP(mcp.id)
                            } else {
                                await config.disableMCP(mcp.id)
                            }
                        }
                    }
                ))
                .labelsHidden()
            }
        }
    }
}
```

## 5. Implementación del Servidor — Config API Module

### 5.1 Nuevo módulo: config-handler.js

```javascript
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join } from 'path';
import os from 'os';

export class ConfigHandler {
    constructor(openclawBridge, config) {
        this.bridge = openclawBridge;
        this.config = config;
        this.logSubscribers = new Set();
    }
    
    async handleConfigMessage(ws, msg) {
        switch (msg.type) {
            case 'config_get':
                return this.handleGet(ws, msg);
            case 'config_set':
                return this.handleSet(ws, msg);
            case 'config_action':
                return this.handleAction(ws, msg);
            case 'logs_subscribe':
                return this.handleLogsSubscribe(ws, msg);
            default:
                return null; // No es un mensaje de config
        }
    }
    
    async handleGet(ws, msg) {
        const { section } = msg.payload;
        let data;
        
        switch (section) {
            case 'openclaw':
                data = await this.getOpenClawConfig();
                break;
            case 'mcps':
                data = await this.getMCPsConfig();
                break;
            case 'system':
                data = this.getSystemStatus();
                break;
            case 'relay':
                data = this.getRelayConfig();
                break;
        }
        
        ws.send(JSON.stringify({
            type: 'config_data',
            request_id: msg.id,
            payload: { section, data }
        }));
    }
    
    async handleAction(ws, msg) {
        const { action, ...params } = msg.payload;
        let result;
        
        switch (action) {
            case 'restart_openclaw':
                await this.bridge.stop();
                await this.bridge.start();
                result = { success: true, message: 'OpenClaw reiniciado' };
                break;
                
            case 'enable_mcp':
                result = await this.enableMCP(params.mcp_id);
                break;
                
            case 'disable_mcp':
                result = await this.disableMCP(params.mcp_id);
                break;
                
            case 'test_mcp':
                result = await this.testMCP(params.mcp_id);
                break;
                
            case 'regenerate_token':
                result = this.regenerateToken();
                break;
                
            default:
                result = { success: false, message: `Acción desconocida: ${action}` };
        }
        
        ws.send(JSON.stringify({
            type: 'config_result',
            request_id: msg.id,
            payload: result
        }));
    }
    
    getSystemStatus() {
        const cpus = os.cpus();
        const totalMem = os.totalmem();
        const freeMem = os.freemem();
        
        return {
            mac: {
                hostname: os.hostname(),
                os_version: `macOS ${os.release()}`,
                cpu_usage: this.getCPUUsage(cpus),
                memory_used_gb: ((totalMem - freeMem) / 1e9).toFixed(1),
                memory_total_gb: (totalMem / 1e9).toFixed(1),
                uptime_hours: (os.uptime() / 3600).toFixed(1)
            },
            openclaw: {
                status: this.bridge.isReady ? 'running' : 'stopped',
                processing: this.bridge.isProcessing
            },
            relay: {
                status: 'running',
                uptime_seconds: process.uptime()
            }
        };
    }
    
    // Leer configuración de OpenClaw desde sus archivos de config
    async getOpenClawConfig() {
        // Adaptar rutas según dónde OpenClaw guarda su config
        const configPaths = [
            join(os.homedir(), '.openclaw', 'config.json'),
            join(os.homedir(), '.config', 'openclaw', 'config.json'),
            join(os.homedir(), '.openclaw.json')
        ];
        
        for (const path of configPaths) {
            if (existsSync(path)) {
                try {
                    return JSON.parse(readFileSync(path, 'utf8'));
                } catch (e) {
                    return { error: `Error leyendo config: ${e.message}`, path };
                }
            }
        }
        
        return { error: 'Config file not found', searched: configPaths };
    }
    
    // Leer lista de MCPs configurados
    async getMCPsConfig() {
        // Adaptar según cómo OpenClaw gestiona MCPs
        const mcpConfigPath = join(os.homedir(), '.openclaw', 'mcps.json');
        
        if (existsSync(mcpConfigPath)) {
            try {
                const config = JSON.parse(readFileSync(mcpConfigPath, 'utf8'));
                return { installed: config.mcps || [] };
            } catch (e) {
                return { error: e.message };
            }
        }
        
        return { installed: [] };
    }
}
```

## 6. Seguridad

### 6.1 Permisos de configuración

No todas las acciones deben estar disponibles sin protección adicional:

| Acción | Nivel de seguridad |
|--------|-------------------|
| Ver estado | Normal (token estándar) |
| Ver configuración | Normal |
| Ver logs | Normal |
| Cambiar configuración | Requiere confirmación en app |
| Reiniciar OpenClaw | Requiere confirmación |
| Instalar/Desinstalar MCP | Requiere confirmación + PIN |
| Regenerar token | Requiere confirmación + PIN |
| Modificar API keys | Requiere confirmación + PIN |

### 6.2 PIN de seguridad

Para acciones sensibles, el usuario configura un PIN de 4-6 dígitos en la primera configuración. Este PIN se envía como campo adicional en las acciones protegidas:

```json
{
  "type": "config_action",
  "id": "uuid",
  "payload": {
    "action": "install_mcp",
    "mcp_url": "...",
    "security_pin": "1234"
  }
}
```

### 6.3 Enmascaramiento de credenciales

Las API keys y tokens nunca se envían completos al cliente. Se enmascaran:
```
"sk-ant-api03-abc...xyz" → "sk-ant-...xyz"
```

Para editar una API key, se envía el valor completo nuevo (no se puede "ver" el actual).

## 7. Integración en el Roadmap

Este módulo se desarrolla en el **Sprint 4** (Pulido y Producción) como parte de la sección de Settings. Las vistas básicas pueden empezar en Sprint 2 junto con las Settings de voz.

### Orden de implementación sugerido:
1. **Config API en el relay server** — Leer configuración de OpenClaw
2. **Vista de estado del sistema** — Monitorización básica
3. **Vista de logs** — Ver logs en tiempo real
4. **Gestión de MCPs** — Listar, activar/desactivar
5. **Edición de configuración** — Cambiar parámetros de OpenClaw
6. **Acciones avanzadas** — Instalar MCPs, backup, etc.
