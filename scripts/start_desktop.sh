#!/bin/bash
# Gemma4all — Start desktop runtime
# Usage:
#   bash scripts/start_desktop.sh              # E2B model, GPU backend
#   MODEL=e4b bash scripts/start_desktop.sh    # E4B model, GPU backend
#   BACKEND=cpu bash scripts/start_desktop.sh  # CPU backend (non-Apple-Silicon)
#
# Environment overrides (all optional):
#   CONTROL_PLANE_URL   default: http://localhost:3000
#   MODEL               e2b (default) | e4b | full path
#   BACKEND             gpu (default on macOS) | cpu
#   POLL_INTERVAL_S     default: 10
#   DEVICE_NAME         default: hostname
#   DEV_BYPASS_AUTH     default: false; for curl testing, start control plane with:
#                       DEV_BYPASS_AUTH=true npm start

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$REPO_ROOT/services/desktop-runtime"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓  $1${NC}"; }
warn() { echo -e "${YELLOW}→  $1${NC}"; }
fail() { echo -e "${RED}✗  $1${NC}"; exit 1; }
info() { echo -e "${CYAN}    $1${NC}"; }

echo ""
echo -e "${CYAN}━━  Gemma4all Desktop Runtime  ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Resolve model path ────────────────────────────────────────────────────────
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
MODEL_CHOICE="${MODEL:-e2b}"

case "$MODEL_CHOICE" in
  e2b)   RESOLVED_MODEL="$MODELS_DIR/gemma-4-E2B-it.litertlm" ;;
  e4b)   RESOLVED_MODEL="$MODELS_DIR/gemma-4-E4B-it.litertlm" ;;
  /*)    RESOLVED_MODEL="$MODEL_CHOICE" ;;           # absolute path passed directly
  *)     RESOLVED_MODEL="$MODELS_DIR/$MODEL_CHOICE" ;;
esac

if [[ ! -f "$RESOLVED_MODEL" ]]; then
  fail "Model file not found: $RESOLVED_MODEL
  Run: bash scripts/check_models.sh
  Or:  bash scripts/check_models.sh --e4b  (to also download E4B)"
fi
ok "Model: $RESOLVED_MODEL ($(du -sh "$RESOLVED_MODEL" | cut -f1))"

# ── Resolve backend ───────────────────────────────────────────────────────────
# Auto-detect Apple Silicon → GPU (Metal); fall back to CPU
if [[ -z "${BACKEND:-}" ]]; then
  if [[ "$(uname -m)" == "arm64" && "$(uname -s)" == "Darwin" ]]; then
    BACKEND="gpu"
  else
    BACKEND="cpu"
  fi
fi
ok "Backend: $BACKEND"

# ── Control plane URL ─────────────────────────────────────────────────────────
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:3000}"
ok "Control plane: $CONTROL_PLANE_URL"

# ── Check uv is available ─────────────────────────────────────────────────────
if ! command -v uv &>/dev/null; then
  fail "uv not found. Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi
ok "uv: $(uv --version)"

# ── Check control plane is reachable ─────────────────────────────────────────
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 \
  "$CONTROL_PLANE_URL/v1/tasks" \
  -H "Authorization: ApiKey probe" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "401" ]]; then
  ok "Control plane reachable (got expected 401)"
elif [[ "$HTTP_CODE" == "200" && "${DEV_BYPASS_AUTH:-false}" == "true" ]]; then
  ok "Control plane reachable (auth bypass enabled)"
elif [[ "$HTTP_CODE" == "000" ]]; then
  warn "Control plane not reachable at $CONTROL_PLANE_URL"
  warn "Make sure it is running: cd services/control-plane && npm start"
  warn "For curl testing: cd services/control-plane && DEV_BYPASS_AUTH=true npm start"
  echo ""
  read -p "  Continue anyway? [y/N] " -n 1 -r
  echo ""
  [[ "$REPLY" =~ ^[Yy]$ ]] || exit 1
else
  warn "Control plane responded HTTP $HTTP_CODE (expected 401) — continuing"
fi

echo ""
echo -e "${CYAN}━━  Starting runtime…  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
info "Press Ctrl+C to stop"
echo ""

# ── Launch ────────────────────────────────────────────────────────────────────
export DEV_BYPASS_AUTH="${DEV_BYPASS_AUTH:-false}"

cd "$RUNTIME_DIR"
exec env \
  CONTROL_PLANE_URL="$CONTROL_PLANE_URL" \
  MODEL_PATH="$RESOLVED_MODEL" \
  BACKEND="$BACKEND" \
  POLL_INTERVAL_S="${POLL_INTERVAL_S:-10}" \
  DEVICE_NAME="${DEVICE_NAME:-$(hostname -s)}" \
  DEV_BYPASS_AUTH="$DEV_BYPASS_AUTH" \
  uv run desktop-runtime
