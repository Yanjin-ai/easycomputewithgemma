#!/usr/bin/env bash
# Gemma4all — Build, package, and upload the macOS menu bar app release.
#
# Usage:
#   bash scripts/release_macos.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_YML="$REPO_ROOT/apps/macos-menubar/project.yml"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓  $1${NC}"; }
fail() { echo -e "${RED}✗  $1${NC}"; exit 1; }
info() { echo -e "${CYAN}    $1${NC}"; }

bash "$REPO_ROOT/scripts/build_macos_app.sh"
bash "$REPO_ROOT/scripts/create_dmg.sh"

if ! command -v gh &>/dev/null; then
  fail "请先安装并登录 GitHub CLI：brew install gh && gh auth login"
fi

VERSION=$(grep -E 'CFBundleShortVersionString:' "$PROJECT_YML" | head -1 | sed -E 's/.*CFBundleShortVersionString:[[:space:]]*"?([^"]+)"?.*/\1/')
[[ -z "$VERSION" ]] && fail "无法从 $PROJECT_YML 读取 CFBundleShortVersionString"

DMG_PATH="/tmp/GemmaMenuBar-${VERSION}.dmg"
[[ ! -f "$DMG_PATH" ]] && fail "未找到 $DMG_PATH"

gh release create "v${VERSION}" \
  "$DMG_PATH" \
  --title "GemmaMenuBar v${VERSION}" \
  --notes "$(cat <<'EOF'
## 安装方法

1. 先安装后端服务（如未安装）：
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Yanjin-ai/easycompute/main/scripts/install.sh | bash
   ```
2. 下载上方 DMG，拖入 /Applications
3. 右键 GemmaMenuBar.app → **打开**（首次需要绕过 Gatekeeper）

> 注：当前版本未经 Apple 公证，首次打开需右键→打开。
EOF
)"

ok "GitHub Release 已创建：v${VERSION}"
info "已上传：$DMG_PATH"
