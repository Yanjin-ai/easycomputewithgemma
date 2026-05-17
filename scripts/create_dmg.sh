#!/usr/bin/env bash
# Gemma4all — Package the macOS menu bar app into a distributable DMG.
#
# Usage:
#   bash scripts/create_dmg.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_YML="$REPO_ROOT/apps/macos-menubar/project.yml"
APP_DIR="/tmp/GemmaMenuBar-build"
APP_PATH="$APP_DIR/GemmaMenuBar.app"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓  $1${NC}"; }
fail() { echo -e "${RED}✗  $1${NC}"; exit 1; }
info() { echo -e "${CYAN}    $1${NC}"; }

if ! command -v create-dmg &>/dev/null; then
  fail "请先安装：brew install create-dmg"
fi

if [[ ! -d "$APP_PATH" ]]; then
  fail "未找到 $APP_PATH，请先运行：bash scripts/build_macos_app.sh"
fi

VERSION=$(grep -E 'CFBundleShortVersionString:' "$PROJECT_YML" | head -1 | sed -E 's/.*CFBundleShortVersionString:[[:space:]]*"?([^"]+)"?.*/\1/')
[[ -z "$VERSION" ]] && fail "无法从 $PROJECT_YML 读取 CFBundleShortVersionString"

DMG_PATH="/tmp/GemmaMenuBar-${VERSION}.dmg"
rm -f "$DMG_PATH"

create_dmg_args=(
  --volname "GemmaMenuBar $VERSION"
  --window-pos 200 120
  --window-size 600 400
  --icon-size 100
  --icon "GemmaMenuBar.app" 175 190
  --hide-extension "GemmaMenuBar.app"
  --app-drop-link 425 190
  --no-internet-enable
)

ICON_PATH="$REPO_ROOT/apps/macos-menubar/AppIcon.icns"
if [[ -f "$ICON_PATH" ]]; then
  create_dmg_args=(--volicon "$ICON_PATH" "${create_dmg_args[@]}")
fi

create-dmg "${create_dmg_args[@]}" "$DMG_PATH" "$APP_DIR/"

ok "DMG 已生成：$DMG_PATH"
info "分发给用户：将 DMG 上传到 GitHub Releases"
info "用户首次打开：右键 GemmaMenuBar.app → 打开（绕过 Gatekeeper）"
info "或命令行移除隔离：xattr -rd com.apple.quarantine /Applications/GemmaMenuBar.app"
