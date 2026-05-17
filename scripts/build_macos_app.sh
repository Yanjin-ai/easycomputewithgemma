#!/usr/bin/env bash
# Gemma4all — Build the macOS menu bar app for local DMG packaging.
#
# Usage:
#   bash scripts/build_macos_app.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/apps/macos-menubar"
DERIVED_DATA="/tmp/GemmaMenuBar-dd"
OUTPUT_DIR="/tmp/GemmaMenuBar-build"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓  $1${NC}"; }
fail() { echo -e "${RED}✗  $1${NC}"; exit 1; }
info() { echo -e "${CYAN}    $1${NC}"; }

if ! command -v xcodegen &>/dev/null; then
  fail "请先安装：brew install xcodegen"
fi

cd "$APP_DIR"
xcodegen generate

build_args=(
  -project "$APP_DIR/GemmaMenuBar.xcodeproj"
  -scheme GemmaMenuBar
  -configuration Release
  -destination "generic/platform=macOS"
  -derivedDataPath "$DERIVED_DATA"
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_REQUIRED=NO
  ONLY_ACTIVE_ARCH=NO
  build
)

if command -v xcpretty &>/dev/null; then
  xcodebuild "${build_args[@]}" | xcpretty
else
  xcodebuild "${build_args[@]}"
fi

APP_PATH=$(find "$DERIVED_DATA" -name "GemmaMenuBar.app" -not -path "*/Index*" | head -1)
[[ -z "$APP_PATH" ]] && fail "构建失败，未找到 .app"

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/GemmaMenuBar.app"
cp -R "$APP_PATH" "$OUTPUT_DIR/"

ok "App 构建完成：$OUTPUT_DIR/GemmaMenuBar.app"
info "打包 DMG：bash scripts/create_dmg.sh"
info "本地测试：open $OUTPUT_DIR/GemmaMenuBar.app"
