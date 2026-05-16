#!/usr/bin/env bash
# Gemma4all — One-click installer for macOS
#
# Usage (curl | bash):
#   curl -fsSL https://raw.githubusercontent.com/Yanjin-ai/easycompute/main/scripts/install.sh | bash
#
# Or with options:
#   MODEL=e4b bash install.sh
#   SKIP_MODEL=true bash install.sh   # CI / fast install, skip model download
#
# Supported environment variables:
#   GEMMA4ALL_DIR   Install directory (default: ~/Applications/Gemma4all)
#   MODEL           Model variant: e2b (default) or e4b
#   SKIP_MODEL      Set to "true" to skip model download

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
INSTALL_DIR="${GEMMA4ALL_DIR:-$HOME/Applications/Gemma4all}"
MODEL="${MODEL:-e2b}"
SKIP_MODEL="${SKIP_MODEL:-false}"

# this script to a GitHub Release or linking it from a README.
REPO_URL="${GEMMA4ALL_REPO_URL:-https://github.com/Yanjin-ai/easycompute.git}"

# ── Color helpers ──────────────────────────────────────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

step() { echo -e "\n${CYAN}${BOLD}$1${NC}"; }
ok()   { echo -e "${GREEN}✓  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠  $1${NC}"; }
fail() { echo -e "${RED}✗  $1${NC}"; exit 1; }

# ── Step counter ───────────────────────────────────────────────────────────────
TOTAL_STEPS=8
s=0
next_step() {
  s=$((s + 1))
  step "[ $s/$TOTAL_STEPS ] $1"
}

# ══════════════════════════════════════════════════════════════════════════════
# Step 1 — System requirements
# ══════════════════════════════════════════════════════════════════════════════
next_step "检查系统要求..."

# macOS only
if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "Gemma4all 仅支持 macOS，当前系统：$(uname -s)"
fi

# macOS 13+
MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="$(echo "$MACOS_VERSION" | awk -F. '{print $1}')"
if [[ "$MACOS_MAJOR" -lt 13 ]]; then
  fail "需要 macOS 13（Ventura）或更高版本，当前版本：$MACOS_VERSION"
fi

# Architecture check (informational)
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
  fail "不支持的 CPU 架构：$ARCH（需要 Apple Silicon 或 Intel）"
fi

# Disk space: require >= 5 GB free in $HOME
AVAIL_GB="$(df -BG "$HOME" | awk 'NR==2 {gsub("G","",$4); print $4}')"
if [[ "$AVAIL_GB" -lt 5 ]]; then
  fail "磁盘空间不足：$HOME 当前可用 ${AVAIL_GB}GB，安装需要至少 5GB"
fi

ok "完成（macOS $MACOS_VERSION，$ARCH，磁盘剩余 ${AVAIL_GB}GB）"

# ══════════════════════════════════════════════════════════════════════════════
# Step 2 — Homebrew
# ══════════════════════════════════════════════════════════════════════════════
next_step "检查 / 安装 Homebrew..."

if ! command -v brew &>/dev/null; then
  warn "未检测到 Homebrew，开始安装..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || fail "Homebrew 安装失败，请访问 https://brew.sh 手动安装后重试"

  # Apple Silicon: add brew to PATH for the current session
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

ok "完成（$(brew --version | head -1)）"

# ══════════════════════════════════════════════════════════════════════════════
# Step 3 — uv (Python package manager)
# ══════════════════════════════════════════════════════════════════════════════
next_step "检查 / 安装 uv（Python 包管理器）..."

if ! command -v uv &>/dev/null; then
  warn "未检测到 uv，开始安装..."
  if command -v brew &>/dev/null; then
    brew install uv \
      || { warn "brew install uv 失败，尝试官方脚本...";
           curl -LsSf https://astral.sh/uv/install.sh | sh
           # Make uv available in the current session
           export PATH="$HOME/.local/bin:$PATH"; }
  else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

command -v uv &>/dev/null || fail "uv 安装失败，请访问 https://docs.astral.sh/uv/ 手动安装后重试"
ok "完成（$(uv --version)）"

# ══════════════════════════════════════════════════════════════════════════════
# Step 4 — Clone or update repository
# ══════════════════════════════════════════════════════════════════════════════
next_step "获取 Gemma4all 源代码..."

if [[ -d "$INSTALL_DIR/.git" ]]; then
  warn "检测到已有安装，执行更新..."
  git -C "$INSTALL_DIR" pull \
    || fail "仓库更新失败，请检查网络连接或手动运行 git pull"
else
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR" \
    || fail "仓库克隆失败（URL: $REPO_URL），请检查网络连接"
fi

ok "完成（安装目录：$INSTALL_DIR）"

# ══════════════════════════════════════════════════════════════════════════════
# Step 5 — Node.js dependencies (control-plane)
# ══════════════════════════════════════════════════════════════════════════════
next_step "安装 Node.js 依赖（control-plane）..."

if ! command -v node &>/dev/null; then
  warn "未检测到 Node.js，开始安装..."
  brew install node \
    || fail "Node.js 安装失败，请运行 brew install node 后重试"
fi

(
  cd "$INSTALL_DIR/services/control-plane"
  npm install --production \
    || fail "Node.js 依赖安装失败，请检查网络连接"
  npm run build \
    || fail "control-plane 编译失败，请查看上方错误信息"
) || exit 1

ok "完成（node $(node --version)）"

# ══════════════════════════════════════════════════════════════════════════════
# Step 6 — Python dependencies (desktop-runtime)
# ══════════════════════════════════════════════════════════════════════════════
next_step "安装 Python 依赖（desktop-runtime）..."

(
  cd "$INSTALL_DIR/services/desktop-runtime"
  uv sync \
    || fail "Python 依赖安装失败，请检查网络连接或运行 uv sync 查看详细错误"
) || exit 1

ok "完成"

# ══════════════════════════════════════════════════════════════════════════════
# Step 7 — Download model
# ══════════════════════════════════════════════════════════════════════════════
next_step "下载 Gemma 4 模型（$MODEL，可能需要 10–30 分钟）..."

if [[ "$SKIP_MODEL" == "true" ]]; then
  warn "SKIP_MODEL=true，跳过模型下载（CI 模式）"
else
  MODEL_SCRIPT="$INSTALL_DIR/scripts/check_models.sh"
  if [[ ! -f "$MODEL_SCRIPT" ]]; then
    warn "未找到 $MODEL_SCRIPT，跳过模型下载"
    warn "安装完成后请手动运行：bash $INSTALL_DIR/scripts/check_models.sh"
  else
    if [[ "$MODEL" == "e4b" ]]; then
      bash "$MODEL_SCRIPT" --e4b \
        || { warn "模型下载失败，请稍后手动运行：bash $INSTALL_DIR/scripts/check_models.sh --e4b"; }
    else
      bash "$MODEL_SCRIPT" \
        || { warn "模型下载失败，请稍后手动运行：bash $INSTALL_DIR/scripts/check_models.sh"; }
    fi
  fi
fi

ok "完成"

# ══════════════════════════════════════════════════════════════════════════════
# Step 8 — launchd agent (auto-start on login)
# ══════════════════════════════════════════════════════════════════════════════
next_step "安装开机自启动（launchd agent）..."

AUTOSTART_SCRIPT="$INSTALL_DIR/scripts/install_autostart.sh"
if [[ ! -f "$AUTOSTART_SCRIPT" ]]; then
  warn "未找到 $AUTOSTART_SCRIPT，跳过 launchd 安装"
else
  bash "$AUTOSTART_SCRIPT" --model "$MODEL" \
    || warn "launchd agent 安装失败，Gemma4all 不会在登录时自动启动"
fi

ok "完成"

# ══════════════════════════════════════════════════════════════════════════════
# Done!
# ══════════════════════════════════════════════════════════════════════════════
LOCAL_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "（未检测到 IP，请前往 System Settings → Network 查看）")"

echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}✓  Gemma4all 安装完成！${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "下一步："
echo -e "  1. 打开 iPhone，安装 Gemma4all App"
echo -e "  2. 你的 Mac IP 地址："
echo -e "       ${CYAN}${LOCAL_IP}${NC}"
echo -e "  3. 在 iOS App 的设置里填入："
echo -e "       ${CYAN}http://${LOCAL_IP}:3000${NC}"
echo ""
echo -e "日志查看："
echo -e "  tail -f /tmp/gemma4all.stdout.log"
echo -e "  tail -f /tmp/gemma4all.stderr.log"
echo ""
echo -e "卸载："
echo -e "  bash $INSTALL_DIR/scripts/install_autostart.sh --uninstall"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
