#!/usr/bin/env bash
#
# Expose the relay's HTTPS endpoint (port 8765) to the public internet via
# Tailscale Funnel, so ElevenLabs Conversational AI agents can reach our
# OpenAI-compatible /v1/chat/completions endpoint as a Custom LLM.
#
# Usage:
#   server/openclaw-relay-server/scripts/setup-funnel.sh           # set up
#   server/openclaw-relay-server/scripts/setup-funnel.sh off       # tear down
#   server/openclaw-relay-server/scripts/setup-funnel.sh status    # show state
#
# Prerequisites:
#   - Tailscale installed and signed in (https://tailscale.com)
#   - Funnel enabled for this device in the admin console:
#       https://login.tailscale.com/admin/acls/file
#     (Add "funnel" attribute and grant to this node — the script prints
#      a hint if Funnel is rejected.)
#
# This script does NOT require sudo. Funnel + Serve config is per-user.

set -euo pipefail

RELAY_PORT="${OPENCLAW_RELAY_PORT:-8765}"
FUNNEL_PORT=443  # Funnel only allows 443, 8443, or 10000

# Locate the Tailscale CLI. The Mac App Store version ships only the GUI
# bundle; its main binary doubles as the CLI when invoked with subcommands.
find_ts() {
    if command -v tailscale >/dev/null 2>&1; then
        command -v tailscale
        return
    fi
    local candidates=(
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        "/Applications/Tailscale.app/Contents/MacOS/tailscale"
        "/usr/local/bin/tailscale"
        "/opt/homebrew/bin/tailscale"
    )
    for c in "${candidates[@]}"; do
        if [[ -x "$c" ]]; then
            echo "$c"
            return
        fi
    done
    return 1
}

TS="$(find_ts || true)"
if [[ -z "${TS:-}" ]]; then
    cat <<EOF >&2
✘ Tailscale CLI not found.

Install one of:
  - Mac App Store: https://apps.apple.com/us/app/tailscale/id1475387142
  - Standalone:    https://pkgs.tailscale.com/stable/#tap

After install, sign in from the menubar app, then re-run this script.
EOF
    exit 1
fi

ts() { "$TS" "$@"; }

cmd_status() {
    echo "Tailscale CLI: $TS"
    echo
    echo "── tailscale status ────────────────────────────────────────"
    ts status || true
    echo
    echo "── tailscale funnel status ─────────────────────────────────"
    ts funnel status || true
}

cmd_off() {
    echo "Disabling Funnel on port $FUNNEL_PORT…"
    ts funnel --https=$FUNNEL_PORT off || true
    echo "Removing serve config for port $FUNNEL_PORT…"
    ts serve --https=$FUNNEL_PORT off || true
    echo "Done."
}

cmd_on() {
    # 1. Sanity: Tailscale running
    if ! ts status >/dev/null 2>&1; then
        cat <<EOF >&2
✘ Tailscale is not running or not signed in.

Open the menubar app (it should auto-launch) and sign in. Then re-run.
EOF
        exit 1
    fi

    # 2. Sanity: relay listening
    if ! lsof -ti :"$RELAY_PORT" >/dev/null 2>&1; then
        echo "⚠️  No process listening on port $RELAY_PORT — start the relay first:"
        echo "       cd server/openclaw-relay-server && node src/index.js"
        echo "    (continuing anyway — Funnel will just return 502 until it's up.)"
    fi

    # 3. Configure Tailscale Serve to proxy https+insecure://localhost:RELAY_PORT
    #    on the public Funnel port. https+insecure tells Tailscale to skip
    #    cert verification on the loopback side (we use a self-signed cert).
    echo "Configuring tailscale serve  $FUNNEL_PORT  →  https+insecure://localhost:$RELAY_PORT"
    ts serve --bg --https=$FUNNEL_PORT "https+insecure://localhost:$RELAY_PORT"

    echo "Enabling Funnel on port $FUNNEL_PORT"
    if ! ts funnel --bg --https=$FUNNEL_PORT on 2>&1 | tee /tmp/funnel.out; then
        if grep -qi "funnel.*not.*allow\|disabled\|denied" /tmp/funnel.out 2>/dev/null; then
            cat <<EOF >&2

✘ Tailscale rejected the Funnel request.

Funnel must be enabled in your tailnet's admin console. Open:
  https://login.tailscale.com/admin/acls/file

Make sure your policy file grants "funnel" to this device. The minimal
addition looks like:

  "nodeAttrs": [
    { "target": ["autogroup:member"], "attr": ["funnel"] }
  ]

Then re-run this script.
EOF
            exit 1
        fi
        exit 1
    fi
    rm -f /tmp/funnel.out

    echo
    echo "── Funnel is up. Public URL & smoke tests ──────────────────"
    public_url=$(ts funnel status 2>/dev/null | awk '/^https:\/\//{print $1; exit}')
    if [[ -z "$public_url" ]]; then
        ts funnel status
        echo "(could not auto-detect URL; copy from above)"
    else
        echo "Public URL: $public_url"
        echo
        echo "→ Health check:"
        curl --max-time 8 --silent --fail "$public_url/health" \
            && echo \
            || echo "(health check failed — give Tailscale ~10s to propagate the cert and retry)"
        echo
        echo "→ ElevenLabs Custom LLM config:"
        echo "   Server URL:  $public_url/v1/chat/completions"
        echo "   Model ID:    openclaw    (or run: curl -H 'Authorization: Bearer \$TOKEN' $public_url/v1/models )"
        echo "   API Key:     <your relay authToken — see ~/.openclaw-relay/config.json>"
    fi
}

case "${1:-on}" in
    on|up|start) cmd_on ;;
    off|down|stop) cmd_off ;;
    status|"") cmd_status ;;
    *)
        echo "usage: $0 [on|off|status]" >&2
        exit 2
        ;;
esac
