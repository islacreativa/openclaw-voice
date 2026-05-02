# Custom LLM — Conectar el agente Realtime de ElevenLabs a tu OpenClaw

Por defecto, el modo **Realtime Voice** de la app usa el LLM que tenga
configurado tu agente en el panel de ElevenLabs (Claude/GPT/Gemini en su
nube). Para que las respuestas vengan de **tu OpenClaw del Mac**, hay que
configurar el agente con **Custom LLM** apuntando al endpoint
OpenAI-compatible del relay (`/v1/chat/completions`).

El relay ya implementa este endpoint (`server/openclaw-relay-server/src/server/http-api.js`).
La pieza que falta es exponerlo públicamente con un cert TLS válido — la
nube de ElevenLabs no puede llegar a tu LAN ni confía en tu cert
auto-firmado. Para eso usamos **Tailscale Funnel**.

## TL;DR

```bash
# 1. En el Mac
server/openclaw-relay-server/scripts/setup-funnel.sh on

# Imprime una URL pública tipo:
#   https://tu-mac.tu-tailnet.ts.net

# 2. En el panel de ElevenLabs (Conversational AI → tu agente → LLM)
#   - Provider: Custom LLM
#   - Server URL: https://tu-mac.tu-tailnet.ts.net/v1/chat/completions
#   - Model ID:   openclaw    (o el id que devuelva /v1/models)
#   - API Key:    <tu authToken — sale en el QR del relay>

# 3. Vuelve a la app, "End Conversation" → "Start Conversation"
```

A partir de ahí, las respuestas de voz vendrán de tu OpenClaw real.

---

## Por qué Tailscale Funnel

| Requisito Custom LLM | Solución |
|---|---|
| URL pública desde internet | Funnel expone el Mac en `*.ts.net` |
| Cert TLS válido | Tailscale gestiona Let's Encrypt automáticamente |
| Sin abrir puertos del router | Funnel hace túnel saliente |
| Auth | El relay ya valida `Authorization: Bearer <token>` |

Alternativas: Cloudflare Tunnel, ngrok, IP pública + Let's Encrypt. Funcionan
todas igual de bien; este repo trae el atajo para Tailscale porque ya lo
usamos para el acceso remoto desde móvil.

## Prerequisitos

1. **Tailscale instalado y signado** en el Mac
   - App Store: https://apps.apple.com/us/app/tailscale/id1475387142
   - O standalone: https://pkgs.tailscale.com/stable/#tap

2. **Funnel habilitado en tu tailnet**
   - Abre https://login.tailscale.com/admin/acls/file
   - Asegúrate de tener `funnel` en `nodeAttrs` para tu cuenta:
     ```jsonc
     "nodeAttrs": [
       { "target": ["autogroup:member"], "attr": ["funnel"] }
     ]
     ```
   - Funnel solo permite los puertos `443`, `8443` y `10000`. El script
     usa `443`.

3. **Relay corriendo** (`node src/index.js` — el script avisa si no lo está
   pero permite seguir; Funnel devolverá 502 hasta que arranques el relay).

## Comandos del script

```bash
scripts/setup-funnel.sh on       # alias: up, start
scripts/setup-funnel.sh off      # alias: down, stop
scripts/setup-funnel.sh status   # alias: <sin argumento>
```

`on` configura `tailscale serve` (loopback `https+insecure://localhost:8765`
→ Funnel `:443`) y prueba el endpoint `/health`.
`off` limpia ambas configuraciones.

## Configurar el agente en ElevenLabs

Después de `setup-funnel.sh on` el script imprime tres datos clave:

```
Public URL: https://tu-mac.tu-tailnet.ts.net
Server URL:  https://tu-mac.tu-tailnet.ts.net/v1/chat/completions
Model ID:    openclaw
API Key:     <tu authToken>
```

En **https://elevenlabs.io/app/conversational-ai** → tu agente → pestaña
**LLM**:

1. **Provider**: Custom LLM
2. **Server URL**: copia el `Server URL` de arriba
3. **Model ID**: pon el id del agente actual (por defecto `openclaw`).
   Si tienes varios y quieres ver la lista exacta:
   ```bash
   TOKEN=$(jq -r .authToken ~/.openclaw-relay/config.json)
   curl -H "Authorization: Bearer $TOKEN" \
     https://tu-mac.tu-tailnet.ts.net/v1/models | jq .
   ```
4. **API Key**: pega tu `authToken`. Lo encuentras con:
   ```bash
   jq -r .authToken ~/.openclaw-relay/config.json
   ```
5. Guarda. **Importante:** vuelve a abrir la conversación en la app —
   ElevenLabs cachea el config del agente al iniciar la sesión.

## Verificación manual

```bash
# 1. /health debería devolver { "status": "ok", ... }
curl https://tu-mac.tu-tailnet.ts.net/health

# 2. /v1/models con auth devuelve lista de agentes
TOKEN=$(jq -r .authToken ~/.openclaw-relay/config.json)
curl -H "Authorization: Bearer $TOKEN" \
  https://tu-mac.tu-tailnet.ts.net/v1/models

# 3. /v1/chat/completions debería forwardear a OpenClaw
curl -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hola"}]}' \
  https://tu-mac.tu-tailnet.ts.net/v1/chat/completions
```

Si `/health` falla con 502 → relay parado. Con 401 → auth incorrecta.
Si la URL no responde tras unos segundos, el cert de Tailscale tarda
~10-30 s en propagarse la primera vez.

## Tear down

```bash
scripts/setup-funnel.sh off
```

Mientras Funnel está activo, **cualquier persona en internet** puede
hacerle requests a tu relay. La auth Bearer evita que las procesen, pero
es buena higiene apagar Funnel cuando no lo usas.

## Modo solo-LAN (sin Funnel)

Si solo quieres usar el modo Realtime con el LLM por defecto de ElevenLabs
(sin tu OpenClaw), no hace falta Funnel. La app sigue funcionando en LAN.

## Troubleshooting

| Síntoma | Causa probable |
|---|---|
| `funnel rejected by tailnet policy` | Falta el `funnel` en `nodeAttrs` (ver Prerequisitos) |
| `Tailscale is stopped` | Abre la app del menubar y firma sesión |
| `502 Bad Gateway` en `/health` | Relay no está corriendo en `:8765` |
| `401` en `/v1/*` | API Key del agente no coincide con el `authToken` |
| El agente sigue respondiendo "como siempre" | ElevenLabs no recargó el config — End/Start conversación, o cierra y abre la pestaña Realtime |
| Audio raro tras conectar | El agente está configurado con output mp3/ulaw — cámbialo a un PCM en su panel |

## Coste y cuotas

- Tailscale: gratis hasta 100 dispositivos / 3 usuarios.
- Funnel: gratis para cualquiera con la attribute `funnel`.
- ElevenLabs: el Custom LLM **no te cobra** por TTS extra; solo pagas por
  los segundos de Realtime Voice como ya hacías. Pero el LLM ya no es
  ellos, así que ahorras el coste del LLM por debajo.
