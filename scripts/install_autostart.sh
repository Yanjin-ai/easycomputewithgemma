#!/usr/bin/env bash
# Gemma4all — Install launchd agent for auto-start on login.
#
# Usage:
#   bash scripts/install_autostart.sh [--model e4b] [--uninstall]
#
# After install, Gemma4all starts automatically on Mac login.
# Logs: /tmp/gemma4all.stdout.log  and  /tmp/gemma4all.stderr.log

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.gemma4all.runtime"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
MODEL="${MODEL:-e2b}"
UNINSTALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      [[ $# -ge 2 ]] || { echo "error: --model requires a value" >&2; exit 1; }
      MODEL="$2"; shift 2 ;;
    --uninstall)
      UNINSTALL=true; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

if $UNINSTALL; then
  echo -e "${CYAN}Uninstalling Gemma4all autostart...${NC}"
  launchctl unload "$PLIST_DEST" 2>/dev/null || true
  rm -f "$PLIST_DEST"
  echo -e "${GREEN}✓ Removed. Gemma4all will no longer start automatically.${NC}"
  exit 0
fi

echo -e "${CYAN}Installing Gemma4all autostart...${NC}"
echo "  Repo : $REPO_ROOT"
echo "  Model: $MODEL"

mkdir -p "$HOME/Library/LaunchAgents"

# Write plist with actual paths substituted
cat > "$PLIST_DEST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-l</string>
    <string>-c</string>
    <string>exec bash "${REPO_ROOT}/scripts/start_all.sh"</string>
  </array>

  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>

  <key>EnvironmentVariables</key>
  <dict>
    <key>MODEL</key>
    <string>${MODEL}</string>
    <key>CONTROL_PLANE_URL</key>
    <string>http://localhost:3000</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>

  <key>StandardOutPath</key>
  <string>/tmp/gemma4all.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/gemma4all.stderr.log</string>

  <key>ThrottleInterval</key>
  <integer>10</integer>
</dict>
</plist>
EOF

# Unload previous version if running
launchctl unload "$PLIST_DEST" 2>/dev/null || true

# Load new version
launchctl load "$PLIST_DEST"

echo -e "${GREEN}✓ Installed and started.${NC}"
echo ""
echo "  Status : launchctl list | grep gemma4all"
echo "  Logs   : tail -f /tmp/gemma4all.stdout.log"
echo "  Errors : tail -f /tmp/gemma4all.stderr.log"
echo "  Remove : bash scripts/install_autostart.sh --uninstall"

# Health check: give the control plane time to boot
echo ""
echo -e "${CYAN}Waiting 20 s for control plane to start...${NC}"
sleep 20
if curl -fsS http://localhost:3000/health >/dev/null 2>&1; then
  echo -e "${GREEN}✓ Control plane is up and healthy.${NC}"
else
  echo -e "${RED}✗ Control plane did not respond on http://localhost:3000/health${NC}"
  echo "  check logs: tail -f /tmp/gemma4all.stderr.log"
fi
