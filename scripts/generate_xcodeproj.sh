#!/bin/bash
# Gemma4all — Generate Xcode projects from project.yml specs
# Requires: xcodegen (brew install xcodegen)
#
# Usage:
#   bash scripts/generate_xcodeproj.sh           # generate both iOS + macOS
#   bash scripts/generate_xcodeproj.sh ios        # iOS only
#   bash scripts/generate_xcodeproj.sh macos      # macOS menu bar only

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓  $1${NC}"; }
warn() { echo -e "${YELLOW}→  $1${NC}"; }
fail() { echo -e "${RED}✗  $1${NC}"; exit 1; }
info() { echo -e "${CYAN}    $1${NC}"; }

TARGET="${1:-both}"

# ── Check xcodegen ────────────────────────────────────────────────────────────
if ! command -v xcodegen &>/dev/null; then
  fail "xcodegen not found.
  Install with: brew install xcodegen
  Then re-run: bash scripts/generate_xcodeproj.sh"
fi
ok "xcodegen $(xcodegen version 2>/dev/null || echo '(version unknown)')"
echo ""

# ── iOS Host ──────────────────────────────────────────────────────────────────
generate_ios() {
  echo -e "${CYAN}━━  Generating GemmaHost.xcodeproj (iOS)  ━━━━━━━━━━━━━━━${NC}"
  local dir="$REPO_ROOT/apps/ios-host"
  if [[ ! -f "$dir/project.yml" ]]; then
    fail "project.yml not found at $dir/project.yml"
  fi
  cd "$dir"
  xcodegen generate --spec project.yml
  ok "Generated: $dir/GemmaHost.xcodeproj"
  info "Open with: open apps/ios-host/GemmaHost.xcodeproj"
  echo ""
}

# ── macOS Menu Bar ────────────────────────────────────────────────────────────
generate_macos() {
  echo -e "${CYAN}━━  Generating GemmaMenuBar.xcodeproj (macOS)  ━━━━━━━━━━${NC}"
  local dir="$REPO_ROOT/apps/macos-menubar"
  if [[ ! -f "$dir/project.yml" ]]; then
    fail "project.yml not found at $dir/project.yml"
  fi
  cd "$dir"
  xcodegen generate --spec project.yml
  ok "Generated: $dir/GemmaMenuBar.xcodeproj"
  info "Open with: open apps/macos-menubar/GemmaMenuBar.xcodeproj"
  echo ""
}

# ── Run ───────────────────────────────────────────────────────────────────────
case "$TARGET" in
  ios)   generate_ios ;;
  macos) generate_macos ;;
  both)  generate_ios; generate_macos ;;
  *)     fail "Unknown target '$TARGET'. Use: ios | macos | both" ;;
esac

echo -e "${GREEN}━━  Done  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Next step: open the .xcodeproj in Xcode and set your"
echo "  Development Team in Signing & Capabilities."
echo ""
