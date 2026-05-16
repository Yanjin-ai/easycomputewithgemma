#!/usr/bin/env bash
# Gemma4all — Check autostart and service health.
#
# Usage:
#   bash scripts/check_autostart.sh

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

LABEL="com.gemma4all.runtime"
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:3000}"
PORT="${PORT:-3000}"

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }

echo ""
echo -e "${BOLD}${CYAN}━━ Gemma4all autostart status ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── 1. launchd agent loaded? ──────────────────────────────────────────────────
echo -e "${BOLD}[1] launchd agent${NC}"
if launchctl list 2>/dev/null | grep -q "$LABEL"; then
  PID_COL=$(launchctl list 2>/dev/null | awk -v label="$LABEL" '$0 ~ label {print $1}')
  STATUS_COL=$(launchctl list 2>/dev/null | awk -v label="$LABEL" '$0 ~ label {print $2}')
  if [[ "$PID_COL" != "-" && -n "$PID_COL" ]]; then
    ok "Agent loaded and running (PID $PID_COL)"
  else
    warn "Agent loaded but not currently running (last exit status: $STATUS_COL)"
  fi
else
  fail "Agent not loaded — run: bash scripts/install_autostart.sh"
fi

echo ""

# ── 2. Control plane responding? ─────────────────────────────────────────────
echo -e "${BOLD}[2] Control plane${NC}"
HEALTH_RESP=$(curl -fsS --max-time 3 "${CONTROL_PLANE_URL}/health" 2>/dev/null || true)
if [[ -n "$HEALTH_RESP" ]]; then
  TIMESTAMP=$(echo "$HEALTH_RESP" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4 || true)
  ok "Responding on ${CONTROL_PLANE_URL}/health  (server time: ${TIMESTAMP:-n/a})"
else
  fail "No response from ${CONTROL_PLANE_URL}/health"
  echo "       Logs: tail -f /tmp/gemma4all.stderr.log"
fi

echo ""

# ── 3. Desktop runtime heartbeat ─────────────────────────────────────────────
echo -e "${BOLD}[3] Desktop runtime${NC}"
# Try unauthenticated first (DEV_BYPASS_AUTH), then skip gracefully if 401
RUNTIMES_RESP=$(curl -fsS --max-time 3 \
  -H "Authorization: ApiKey ${API_KEY:-probe}" \
  "${CONTROL_PLANE_URL}/v1/devices" 2>/dev/null || true)

if [[ -z "$RUNTIMES_RESP" ]]; then
  warn "Could not reach ${CONTROL_PLANE_URL}/v1/devices (control plane may be down or auth required)"
else
  # Count online devices
  ONLINE_COUNT=$(echo "$RUNTIMES_RESP" | grep -o '"is_online":true' | wc -l | tr -d ' ')
  TOTAL_COUNT=$(echo "$RUNTIMES_RESP" | grep -o '"device_id"' | wc -l | tr -d ' ')

  if [[ "$ONLINE_COUNT" -gt 0 ]]; then
    ok "$ONLINE_COUNT / $TOTAL_COUNT device(s) online"
    # Print last_seen for each device
    # Use python3 for reliable JSON parsing if available
    if command -v python3 >/dev/null 2>&1; then
      echo "$RUNTIMES_RESP" | python3 - <<'PYEOF'
import sys, json

try:
    data = json.load(sys.stdin)
    devices = data.get("devices", data) if isinstance(data, dict) else data
    if isinstance(devices, list):
        for d in devices:
            name = d.get("device_name") or d.get("device_id", "unknown")
            online = "online" if d.get("is_online") else "offline"
            last_seen = d.get("last_seen_at") or d.get("last_seen") or "n/a"
            print(f"       {name}: {online}, last_seen={last_seen}")
except Exception:
    pass
PYEOF
    fi
  elif [[ "$TOTAL_COUNT" -gt 0 ]]; then
    warn "$TOTAL_COUNT device(s) registered but none online"
  else
    warn "No devices registered — desktop runtime may not have connected yet"
    echo "       Logs: tail -f /tmp/gemma4all.stderr.log"
  fi
fi

echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Full logs  : tail -f /tmp/gemma4all.stdout.log"
echo "  Error logs : tail -f /tmp/gemma4all.stderr.log"
echo "  Install    : bash scripts/install_autostart.sh [--model e4b]"
echo "  Uninstall  : bash scripts/install_autostart.sh --uninstall"
echo ""
