#!/bin/bash
# Gemma4all — Model checker and downloader
# Usage: bash scripts/check_models.sh [--e4b]
# Default: checks E2B only. Pass --e4b to also check/download the 3.7GB E4B model.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓  $1${NC}"; }
warn() { echo -e "${YELLOW}→  $1${NC}"; }
fail() { echo -e "${RED}✗  $1${NC}"; exit 1; }
info() { echo -e "${CYAN}    $1${NC}"; }

MODELS_DIR="${MODELS_DIR:-$HOME/models}"
WANT_E4B=false
[[ "${1:-}" == "--e4b" ]] && WANT_E4B=true

E2B_FILE="$MODELS_DIR/gemma-4-E2B-it.litertlm"
E4B_FILE="$MODELS_DIR/gemma-4-E4B-it.litertlm"
E2B_REPO="litert-community/gemma-4-E2B-it-litert-lm"
E4B_REPO="litert-community/gemma-4-E4B-it-litert-lm"
E2B_SIZE="~2.6 GB"
E4B_SIZE="~3.7 GB"

echo ""
echo -e "${CYAN}━━  Gemma4all model check  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Resolve huggingface-cli (check PATH, then common pip install locations) ────
HF_CLI=""
if command -v huggingface-cli &>/dev/null; then
  HF_CLI="huggingface-cli"
else
  for candidate in \
    "$HOME/.local/bin/huggingface-cli" \
    "$HOME/Library/Python/3.11/bin/huggingface-cli" \
    "$HOME/Library/Python/3.12/bin/huggingface-cli" \
    "$HOME/Library/Python/3.13/bin/huggingface-cli" \
    "$HOME/Library/Python/3.14/bin/huggingface-cli" \
    "/Library/Frameworks/Python.framework/Versions/3.14/bin/huggingface-cli" \
    "/Library/Frameworks/Python.framework/Versions/3.13/bin/huggingface-cli" \
    "/Library/Frameworks/Python.framework/Versions/3.12/bin/huggingface-cli" \
    "/opt/homebrew/bin/huggingface-cli" \
    "/usr/local/bin/huggingface-cli"; do
    if [[ -x "$candidate" ]]; then
      HF_CLI="$candidate"
      break
    fi
  done
fi

if [[ -z "$HF_CLI" ]]; then
  fail "huggingface-cli not found.
  Install with one of:
    pip install huggingface_hub
    pip3 install huggingface_hub
    pipx install huggingface_hub"
fi
ok "huggingface-cli: $HF_CLI"

mkdir -p "$MODELS_DIR"
info "Model directory: $MODELS_DIR"
echo ""

# ── Check E2B ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}━━  Gemma 4 E2B (2B effective params, $E2B_SIZE)  ━━━━━━━━${NC}"
if [[ -f "$E2B_FILE" ]]; then
  SIZE=$(du -sh "$E2B_FILE" 2>/dev/null | cut -f1)
  ok "E2B model present: $E2B_FILE ($SIZE)"
else
  warn "E2B model not found at $E2B_FILE"
  warn "Downloading from HuggingFace ($E2B_SIZE) — this may take a while…"
  "$HF_CLI" download "$E2B_REPO" \
    gemma-4-E2B-it.litertlm \
    --local-dir "$MODELS_DIR" \
    --local-dir-use-symlinks False
  ok "E2B model downloaded: $E2B_FILE"
fi

echo ""

# ── Check E4B (optional) ──────────────────────────────────────────────────────
echo -e "${CYAN}━━  Gemma 4 E4B (4B effective params, $E4B_SIZE)  ━━━━━━━━${NC}"
if [[ -f "$E4B_FILE" ]]; then
  SIZE=$(du -sh "$E4B_FILE" 2>/dev/null | cut -f1)
  ok "E4B model present: $E4B_FILE ($SIZE)"
elif [[ "$WANT_E4B" == "true" ]]; then
  warn "E4B model not found at $E4B_FILE"
  warn "Downloading from HuggingFace ($E4B_SIZE) — this may take a while…"
  "$HF_CLI" download "$E4B_REPO" \
    gemma-4-E4B-it.litertlm \
    --local-dir "$MODELS_DIR" \
    --local-dir-use-symlinks False
  ok "E4B model downloaded: $E4B_FILE"
else
  info "E4B not present (pass --e4b to download the higher-quality 3.7GB model)"
fi

echo ""
echo -e "${GREEN}━━  Summary  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
[[ -f "$E2B_FILE" ]] && ok "E2B ready → $E2B_FILE" || warn "E2B missing"
[[ -f "$E4B_FILE" ]] && ok "E4B ready → $E4B_FILE" || info "E4B not downloaded"
echo ""
echo "  To start desktop runtime with E2B (fast, recommended for most tasks):"
echo "    bash scripts/start_desktop.sh"
echo ""
echo "  To start with E4B (higher quality, slower):"
echo "    MODEL=e4b bash scripts/start_desktop.sh"
echo ""
