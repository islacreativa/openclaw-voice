# Acceso remoto con Tailscale

Este documento describe cómo conectar la app iOS al relay desde fuera de la red local (aeropuerto, 4G/5G, otra WiFi) usando [Tailscale](https://tailscale.com/).

## Por qué Tailscale

El relay escucha en la IP local del Mac (p. ej. `192.168.1.X` o `172.x.x.x`). Esa IP solo es alcanzable desde la misma red. Tailscale crea una red privada WireGuard entre todos tus dispositivos; el Mac y el iPhone obtienen IPs del rango `100.x.x.x` que son accesibles desde cualquier conexión a internet.

## Instalación

### En el Mac (servidor)

1. Descarga Tailscale: https://tailscale.com/download/mac
2. Inicia sesión con tu cuenta.
3. Verifica la IP Tailscale: `ifconfig | grep 100\\.` — debería mostrar algo como `inet 100.83.165.46`.

### En el iPhone

1. Instala Tailscale desde la App Store.
2. Inicia sesión con la misma cuenta.
3. Activa el switch "Connected".

## Configuración del relay

El relay detecta automáticamente la interfaz Tailscale (`utun*` con IP `100.x.x.x`) y la incluye en el QR como `tailscale_url`. Ver `src/config.js` → `getTailscaleIP()` y `getQRData()`.

El QR contiene:

```json
{
  "url": "wss://192.168.1.X:8765/ws",
  "tailscale_url": "wss://100.83.165.46:8765/ws",
  "token": "…",
  "elevenlabs_api_key": "…"
}
```

## Comportamiento en la app

La app iOS guarda ambos URLs (primario y fallback) en Keychain tras escanear el QR. Al conectar:

1. Intenta la URL primaria (red local) con timeout de 6 s.
2. Si no responde con `authOk` en ese tiempo, cancela y prueba el `tailscale_url`.
3. Si ninguno funciona, muestra error.

Tras una desconexión, al reconectar vuelve a empezar por la URL primaria (por si has vuelto a la red local).

Ver:
- `ios/OpenClawVoice/OpenClawVoice/Services/WebSocket/WebSocketManager.swift` → `connect(to:token:fallback:)` y `tryNextCandidateOrFail`
- `ios/OpenClawVoice/OpenClawVoice/Core/Constants.swift` → `connectAttemptTimeout = 6 s`

## Entrada manual

Si prefieres no escanear QR, en la vista de conexión puedes meter ambos URLs a mano. El segundo campo ("Tailscale, optional") se guarda como fallback.

## Troubleshooting

**El iPhone no llega al Mac por Tailscale:**
- Confirma que ambos dispositivos aparecen en el panel de admin de Tailscale (`https://login.tailscale.com/admin/machines`).
- Prueba desde Safari del iPhone: `https://100.x.x.x:8765/ws` — debería devolver `401 Unauthorized`.
- Si el Mac está dormido, Tailscale no enruta. Activa "Wake on network access" en Energy Saver o evita que el Mac entre en modo reposo.

**MagicDNS:**
Si activas MagicDNS puedes usar nombres (`mi-mac.tailnet-xxxx.ts.net`) en lugar de IPs. El relay no los genera por defecto; edita el QR o usa entrada manual.

**Firewall macOS:**
System Settings → Network → Firewall → permite conexiones entrantes para `node`.
