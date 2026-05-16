#!/usr/bin/env bash
# Gemma4all — Installation validator
# Run after install.sh to confirm everything is working.
#
# Usage:
#   bash scripts/validate_install.sh
#   GEMMA4ALL_DIR=~/Applications/EasyCompute bash scripts/validate_install.sh

set -euo pipefail

REPO_ROOT="${GEMMA4ALL_DIR:-$HOME/Applications/EasyCompute}"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

check() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC}  $name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC}  $name"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo -e "${CYAN}━━ EasyCompute 安装验证 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "[ 系统依赖 ]"
check "Node.js 可用"              "command -v node"
check "Python 3 可用"             "command -v python3"
check "uv 可用"                   "command -v uv"
echo ""

echo "[ 项目文件 ]"
check "控制平面代码"              "test -f '$REPO_ROOT/services/control-plane/dist/index.js'"
check "桌面运行时"                "test -f '$REPO_ROOT/services/desktop-runtime/src/desktop_runtime/main.py'"
check "启动脚本"                  "test -f '$REPO_ROOT/scripts/start_all.sh'"
check "模型下载脚本"              "test -f '$REPO_ROOT/scripts/check_models.sh'"
echo ""

echo "[ API Key ]"
check "API key 已生成"            "test -f '$REPO_ROOT/services/desktop-runtime/.desktop_api_key' || test -f '$REPO_ROOT/services/control-plane/.desktop_api_key'"
echo ""

echo "[ AI 模型 ]"
check "E2B 模型文件 (1.5 GB)"    "test -f '$HOME/models/gemma-4-E2B-it.litertlm'"
if ! test -f "$HOME/models/gemma-4-E2B-it.litertlm"; then
  echo "       → 下载: bash '$REPO_ROOT/scripts/check_models.sh'"
fi
echo ""

echo "[ 开机自启 ]"
check "launchd plist 已安装"      "test -f '$HOME/Library/LaunchAgents/com.gemma4all.runtime.plist'"
check "launchd agent 已加载"      "launchctl list | grep -q gemma4all"
if ! launchctl list | grep -q gemma4all 2>/dev/null; then
  echo "       → 安装: bash '$REPO_ROOT/scripts/install_autostart.sh'"
fi
echo ""

echo "[ 服务连通性 ]"
check "控制平面正在响应"          "curl -fsS http://localhost:3000/health -o /dev/null -m 5"
if ! curl -fsS http://localhost:3000/health -o /dev/null -m 5 2>/dev/null; then
  echo "       → 手动启动: bash '$REPO_ROOT/scripts/start_all.sh'"
  echo "       → 查看日志: tail -f /tmp/gemma4all.stderr.log"
fi
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  通过: ${PASS}  失败: ${FAIL}"

if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}  ✓ 所有检查通过，EasyCompute 安装正常${NC}"
  echo ""
  LOCAL_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "未检测到")"
  echo "  你的 Mac IP: ${LOCAL_IP}"
  echo "  iOS App 填入: http://${LOCAL_IP}:3000"
else
  echo -e "${RED}  ✗ ${FAIL} 项失败，请按提示修复${NC}"
  exit 1
fi
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
