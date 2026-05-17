#!/usr/bin/env bash
# Gemma4all — 安全轮换 API Key
#
# 用途：当 API Key 疑似泄露时，完整清除所有本地密钥文件和 SQLite
#       设备记录，重启后自动生成全新 device_id + api_key。
#
# 用法：
#   bash scripts/rotate_keys.sh
#
# 注意：运行前确保已提交或备份所有未保存的工作。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓  $1${NC}"; }
warn() { echo -e "${YELLOW}→  $1${NC}"; }
fail() { echo -e "${RED}✗  $1${NC}"; exit 1; }
info() { echo -e "${CYAN}    $1${NC}"; }

echo ""
echo -e "${CYAN}━━  Gemma4all — API Key 轮换  ━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── 1. 停止服务 ───────────────────────────────────────────────────────────────
echo "[ 停止服务 ]"
launchctl stop com.gemma4all.runtime 2>/dev/null && ok "launchd 服务已停止" || true
pkill -f "desktop.runtime\|desktop_runtime" 2>/dev/null && ok "desktop-runtime 进程已终止" || true
pkill -f "node.*dist/index\|gemma4all-cp" 2>/dev/null && ok "control-plane 进程已终止" || true
sleep 2
echo ""

# ── 2. 删除密钥文件 ───────────────────────────────────────────────────────────
echo "[ 删除密钥文件 ]"

KEY_FILES=(
  "$REPO_ROOT/services/desktop-runtime/.desktop_api_key"
  "$REPO_ROOT/services/desktop-runtime/.desktop_api_key.registration.json"
  "$REPO_ROOT/services/desktop-runtime/checkpoints.db"
  "$REPO_ROOT/services/cloud-runtime/.cloud_api_key"
  "$REPO_ROOT/services/cloud-runtime/.cloud_api_key.registration.json"
)

for f in "${KEY_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    rm -f "$f"
    ok "已删除：$(basename "$f")"
  fi
done
echo ""

# ── 3. 清空 SQLite 设备记录 ───────────────────────────────────────────────────
echo "[ 清空 SQLite 设备记录 ]"

DB_PATHS=(
  "${GEMMA4ALL_DB_PATH:-}"
  "$REPO_ROOT/services/control-plane/gemma4all.db"
  "$HOME/Applications/EasyCompute/services/control-plane/gemma4all.db"
)

DB_CLEANED=false
for DB in "${DB_PATHS[@]}"; do
  [[ -z "$DB" || ! -f "$DB" ]] && continue
  if command -v sqlite3 &>/dev/null; then
    sqlite3 "$DB" "DELETE FROM devices;" 2>/dev/null && \
    sqlite3 "$DB" "DELETE FROM api_keys;" 2>/dev/null || true
    ok "SQLite 已清空：$DB"
    DB_CLEANED=true
    break
  else
    warn "sqlite3 未安装，跳过 DB 清理"
    warn "旧设备记录仍在 DB 中，但因密钥文件已删除，服务会重新注册"
    break
  fi
done

if [[ "$DB_CLEANED" == "false" ]]; then
  warn "未找到 SQLite DB 文件（首次安装或路径不同）——跳过"
fi
echo ""

# ── 4. 重启服务 ───────────────────────────────────────────────────────────────
echo "[ 重启服务 ]"

if launchctl list 2>/dev/null | grep -q gemma4all; then
  launchctl start com.gemma4all.runtime
  ok "launchd 服务已重启"
else
  warn "未检测到 launchd 自启动"
  warn "请手动运行：bash '$REPO_ROOT/scripts/start_all.sh'"
fi
echo ""

# ── 5. 等待新 Key 生成 ────────────────────────────────────────────────────────
echo "[ 等待新 Key 生成 ]"

KEY_FILE="$REPO_ROOT/services/desktop-runtime/.desktop_api_key"
NEW_KEY=""
for i in $(seq 1 60); do
  if [[ -f "$KEY_FILE" ]]; then
    NEW_KEY=$(cat "$KEY_FILE")
    [[ -n "$NEW_KEY" ]] && break
  fi
  sleep 0.5
done

if [[ -n "$NEW_KEY" ]]; then
  ok "新 API Key 已生成：${NEW_KEY:0:8}...${NEW_KEY: -4}"
else
  warn "Key 文件尚未生成（30 秒超时）"
  warn "运行时可能还在启动中，稍后检查：cat '$KEY_FILE'"
fi
echo ""

# ── 6. Health check ───────────────────────────────────────────────────────────
echo "[ 服务健康检查 ]"

if curl -fsS http://localhost:3000/health -m 5 -o /dev/null 2>/dev/null; then
  ok "控制平面响应正常 (http://localhost:3000/health)"
else
  warn "控制平面暂未响应——服务可能还在启动中"
  warn "查看日志：tail -f /tmp/gemma4all.stderr.log"
fi
echo ""

# ── 7. 总结 ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  旧 Key：已吊销（已从磁盘和 DB 中删除）"
if [[ -n "$NEW_KEY" ]]; then
  echo "  新 Key：${NEW_KEY:0:8}...${NEW_KEY: -4}"
fi
echo "  iOS App：无需任何操作（使用 device token，不直接持有 API Key）"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
