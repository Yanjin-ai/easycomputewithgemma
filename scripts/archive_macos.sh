#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓  $1${NC}"; }
warn() { echo -e "${YELLOW}→  $1${NC}"; }
fail() { echo -e "${RED}✗  $1${NC}"; exit 1; }
info() { echo -e "${CYAN}    $1${NC}"; }

echo ""
echo -e "${CYAN}━━  GemmaMenuBar macOS Archive  ━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

[[ -z "${TEAM_ID:-}" ]] && fail "请先 export TEAM_ID=你的10位TeamID
  查找方法：developer.apple.com → Membership → Team ID"

command -v xcodegen &>/dev/null || fail "请先安装：brew install xcodegen"

cd "$REPO_ROOT/apps/macos-menubar"
xcodegen generate

xcodebuild archive \
  -project "$REPO_ROOT/apps/macos-menubar/GemmaMenuBar.xcodeproj" \
  -scheme GemmaMenuBar \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath /tmp/GemmaMenuBar.xcarchive \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  | (command -v xcpretty &>/dev/null && xcpretty || cat)

xcodebuild -exportArchive \
  -archivePath /tmp/GemmaMenuBar.xcarchive \
  -exportOptionsPlist "$REPO_ROOT/apps/macos-menubar/ExportOptions.plist" \
  -exportPath /tmp/GemmaMenuBar-signed-dist/

ok "Archive: /tmp/GemmaMenuBar.xcarchive"
ok "Export:  /tmp/GemmaMenuBar-signed-dist/"
info "公证: xcrun notarytool submit /tmp/GemmaMenuBar-signed-dist/GemmaMenuBar.app \
    --apple-id YOUR_APPLE_ID --team-id $TEAM_ID --wait"
info "Staple: xcrun stapler staple /tmp/GemmaMenuBar-signed-dist/GemmaMenuBar.app"
