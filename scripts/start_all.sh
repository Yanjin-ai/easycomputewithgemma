#!/usr/bin/env bash
# Gemma4all - Start control plane and desktop runtime together.
#
# Environment overrides (all optional):
#   CONTROL_PLANE_URL   default: http://localhost:3000
#   MODEL               e2b (default) | e4b | full path
#   BACKEND             gpu (default on macOS) | cpu
#   POLL_INTERVAL_S     default: 10

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL_PLANE_DIR="$REPO_ROOT/services/control-plane"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

fail() {
  echo -e "${RED}✗  $1${NC}" >&2
  exit 1
}

cleanup() {
  trap - SIGINT SIGTERM EXIT
  echo ""
  echo -e "${CYAN}Stopping Gemma4all services...${NC}"

  if [[ -n "${CP_PID:-}" ]] && kill -0 "$CP_PID" 2>/dev/null; then
    kill "$CP_PID" 2>/dev/null || true
  fi

  if [[ -n "${DESKTOP_PID:-}" ]] && kill -0 "$DESKTOP_PID" 2>/dev/null; then
    kill "$DESKTOP_PID" 2>/dev/null || true
  fi

  if [[ -n "${CP_LOG_PID:-}" ]] && kill -0 "$CP_LOG_PID" 2>/dev/null; then
    kill "$CP_LOG_PID" 2>/dev/null || true
  fi

  if [[ -n "${DESKTOP_LOG_PID:-}" ]] && kill -0 "$DESKTOP_LOG_PID" 2>/dev/null; then
    kill "$DESKTOP_LOG_PID" 2>/dev/null || true
  fi

  for pid in "${CP_PID:-}" "${DESKTOP_PID:-}" "${CP_LOG_PID:-}" "${DESKTOP_LOG_PID:-}"; do
    [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true
  done
}

resolve_desktop_config() {
  MODELS_DIR="${MODELS_DIR:-$HOME/models}"
  MODEL_CHOICE="${MODEL:-e2b}"

  case "$MODEL_CHOICE" in
    e2b) RESOLVED_MODEL="$MODELS_DIR/gemma-4-E2B-it.litertlm" ;;
    e4b) RESOLVED_MODEL="$MODELS_DIR/gemma-4-E4B-it.litertlm" ;;
    /*) RESOLVED_MODEL="$MODEL_CHOICE" ;;
    *) RESOLVED_MODEL="$MODELS_DIR/$MODEL_CHOICE" ;;
  esac

  if [[ ! -f "$RESOLVED_MODEL" ]]; then
    fail "Model file not found: $RESOLVED_MODEL
  Run: bash scripts/check_models.sh
  Or:  bash scripts/check_models.sh --e4b  (to also download E4B)"
  fi

  if [[ -z "${BACKEND:-}" ]]; then
    if [[ "$(uname -m)" == "arm64" && "$(uname -s)" == "Darwin" ]]; then
      BACKEND="gpu"
    else
      BACKEND="cpu"
    fi
  fi

  CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:3000}"
  POLL_INTERVAL_S="${POLL_INTERVAL_S:-10}"
  DEVICE_NAME="${DEVICE_NAME:-$(hostname -s)}"
  DEV_BYPASS_AUTH="${DEV_BYPASS_AUTH:-false}"

  if ! command -v uv >/dev/null 2>&1; then
    fail "uv not found. Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi
}

print_banner() {
  echo ""
  echo -e "${CYAN}━━ Gemma4all — Starting all services ━━━━━━━━━━━━━━━━━━━${NC}"
  echo "   Control plane  →  $CONTROL_PLANE_URL"
  echo "   Desktop model  →  $RESOLVED_MODEL"
  echo "   Backend        →  $BACKEND"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

resolve_desktop_config
print_banner

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gemma4all-start-all.XXXXXX")"
CP_LOG="$LOG_DIR/control-plane.pipe"
DESKTOP_LOG="$LOG_DIR/desktop.pipe"
mkfifo "$CP_LOG" "$DESKTOP_LOG"

trap cleanup SIGINT SIGTERM EXIT

sed -u 's/^/[control-plane] /' <"$CP_LOG" &
CP_LOG_PID=$!

sed -u 's/^/[desktop]       /' <"$DESKTOP_LOG" &
DESKTOP_LOG_PID=$!

(
  cd "$CONTROL_PLANE_DIR"
  exec env \
    CONTROL_PLANE_URL="$CONTROL_PLANE_URL" \
    npm start
) >"$CP_LOG" 2>&1 &
CP_PID=$!

# Wait until control plane is actually listening (up to 15s)
echo -e "${CYAN}  Waiting for control plane...${NC}"
for i in $(seq 1 15); do
  if curl -s -o /dev/null -m 1 "http://localhost:${PORT:-3000}/v1/tasks" \
       -H "Authorization: ApiKey probe" 2>/dev/null; then
    break
  fi
  sleep 1
done

(
  exec env \
    CONTROL_PLANE_URL="$CONTROL_PLANE_URL" \
    MODEL="$RESOLVED_MODEL" \
    BACKEND="$BACKEND" \
    POLL_INTERVAL_S="$POLL_INTERVAL_S" \
    DEVICE_NAME="$DEVICE_NAME" \
    DEV_BYPASS_AUTH="$DEV_BYPASS_AUTH" \
    bash "$REPO_ROOT/scripts/start_desktop.sh"
) >"$DESKTOP_LOG" 2>&1 &
DESKTOP_PID=$!

echo -e "${GREEN}✓  Services started.${NC}"
echo ""
echo -e "${CYAN}━━ Gemma4all running ━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "   Control plane  PID $CP_PID  → $CONTROL_PLANE_URL"
echo "   Desktop        PID $DESKTOP_PID"
echo "   Model:         $RESOLVED_MODEL"
echo "   Press Ctrl+C to stop both services."
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

while true; do
  if ! kill -0 "$CP_PID" 2>/dev/null; then
    wait "$CP_PID"
    exit $?
  fi

  if ! kill -0 "$DESKTOP_PID" 2>/dev/null; then
    wait "$DESKTOP_PID"
    exit $?
  fi

  sleep 1
done
