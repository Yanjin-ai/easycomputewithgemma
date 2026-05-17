#!/usr/bin/env bash
# Gemma4all — Full Feature Test Suite
#
# Tests every implemented capability end-to-end against a live system.
# Run AFTER: bash scripts/start_all.sh (and wait for "Model loaded ✓")
#
# Usage:
#   bash scripts/test_all.sh
#   bash scripts/test_all.sh --url http://192.168.1.10:3000
#   bash scripts/test_all.sh --skip-applescript   # skip macOS Calendar test
#   bash scripts/test_all.sh --only file          # run one scenario
#   bash scripts/test_all.sh --timeout 180        # longer wait per task
#
# Scenarios (13 total):
#   1.  health        Control plane health check (no inference)
#   2.  inference     Pure reasoning — no tools
#   3.  math          Arithmetic with shell tool
#   4.  shell         Shell command execution
#   5.  file_read     Read a local file
#   6.  file_write    Write then read back a file
#   7.  translate     Multilingual output
#   8.  web_fetch     Fetch a URL and extract info
#   9.  web_search    DuckDuckGo search
#   10. applescript   Create a macOS Calendar event
#   11. screenshot    Take a desktop screenshot
#   12. multistep     File read → summarise → shell command (3 tools, 1 task)
#   13. memory        Two sequential tasks — second references first

set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────────────────
BASE_URL="http://localhost:3000"
TIMEOUT_S=120
ONLY_SCENARIO=""
SKIP_APPLESCRIPT=false
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)       BASE_URL="${2%/}";   shift 2 ;;
    --timeout)   TIMEOUT_S="$2";      shift 2 ;;
    --only)      ONLY_SCENARIO="$2";  shift 2 ;;
    --skip-applescript) SKIP_APPLESCRIPT=true; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── Colours ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}✓ PASS${NC}  $1"; }
fail() { echo -e "  ${RED}✗ FAIL${NC}  $1"; }
skip() { echo -e "  ${YELLOW}⊘ SKIP${NC}  $1"; }
info() { echo -e "  ${DIM}$1${NC}"; }

# ── Results accumulator ────────────────────────────────────────────────────────
declare -a RESULTS_NAME RESULTS_VERDICT RESULTS_DETAIL
total_pass=0; total_fail=0; total_skip=0

record() {
  local name="$1" verdict="$2" detail="$3"
  RESULTS_NAME+=("$name")
  RESULTS_VERDICT+=("$verdict")
  RESULTS_DETAIL+=("$detail")
  case "$verdict" in
    PASS) ((total_pass++)) ;;
    FAIL) ((total_fail++)) ;;
    SKIP) ((total_skip++)) ;;
  esac
}

# ── Helpers ────────────────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null || { echo "error: $1 not found" >&2; exit 1; }; }
need curl; need python3

json_get() {
  python3 -c '
import json,sys
data=json.load(sys.stdin)
v=eval(sys.argv[1], {"__builtins__":{}}, {"data":data})
print("" if v is None else json.dumps(v) if isinstance(v,(dict,list)) else v)
' "$1"
}

event_payload() {
  python3 -c '
import json,sys
data=json.load(sys.stdin)
events=data.get("events", data if isinstance(data,list) else [])
for want in sys.argv[1].split(","):
  for e in reversed(events):
    if e.get("event_type")==want:
      print(json.dumps(e.get("payload",{}),ensure_ascii=False))
      raise SystemExit
print("{}")
' "$1"
}

get_summary() {
  python3 -c '
import json,sys
p=json.loads(sys.stdin.read() or "{}")
print(p.get("summary") or p.get("result") or json.dumps(p,ensure_ascii=False))
'
}

count_events() {
  python3 -c '
import json,sys
data=json.load(sys.stdin)
events=data.get("events", data if isinstance(data,list) else [])
print(sum(1 for e in events if e.get("event_type")==sys.argv[1]))
' "$1"
}

contains_ci() { python3 -c "import sys; exit(0 if sys.argv[1].lower() in sys.argv[2].lower() else 1)" "$1" "$2"; }

# ── API key ────────────────────────────────────────────────────────────────────
API_KEY=""
for _p in \
  "$REPO_ROOT/services/desktop-runtime/.desktop_api_key" \
  "$REPO_ROOT/services/control-plane/.desktop_api_key" \
  "${API_KEY_PATH:-/dev/null}"; do
  [[ -f "$_p" ]] || continue
  API_KEY="$(python3 -c 'import sys; print(open(sys.argv[1]).read().strip())' "$_p")"
  [[ -n "$API_KEY" ]] && break
done
[[ -n "$API_KEY" ]] || { echo -e "${RED}error: API key not found${NC}" >&2; exit 1; }

# ── HTTP helpers ───────────────────────────────────────────────────────────────
api_get() {
  curl -fsS "$BASE_URL$1" -H "Authorization: ApiKey $API_KEY"
}

submit_task() {
  local body="$1"
  CREATE_RESP="$(curl -fsS -X POST "$BASE_URL/v1/tasks" \
    -H "Authorization: ApiKey $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$body")"
  TASK_ID="$(printf '%s' "$CREATE_RESP" | json_get \
    'data.get("task_id") or data.get("task",{}).get("task_id")')"
  [[ -n "$TASK_ID" ]] || { echo "error: task_id missing" >&2; return 1; }
}

poll_task() {
  STATE=""; ELAPSED=0
  while [[ $ELAPSED -le $TIMEOUT_S ]]; do
    TASK_RESP="$(api_get "/v1/tasks/$TASK_ID")"
    STATE="$(printf '%s' "$TASK_RESP" | json_get \
      'data.get("current_state") or data.get("state")')"
    printf "\r  ${DIM}[%3ds] state=%-12s${NC}" "$ELAPSED" "$STATE"
    [[ "$STATE" == "completed" || "$STATE" == "failed" || "$STATE" == "cancelled" ]] && break
    [[ $ELAPSED -ge $TIMEOUT_S ]] && break
    sleep 3; ELAPSED=$((ELAPSED+3))
  done
  printf "\r%50s\r" ""   # clear the progress line
  EVENTS="$(api_get "/v1/tasks/$TASK_ID/events?limit=50")"
}

run_scenario() {
  local id="$1" label="$2" body="$3"
  [[ -n "$ONLY_SCENARIO" && "$id" != "$ONLY_SCENARIO" ]] && return 0

  echo ""
  echo -e "${CYAN}▶  $label${NC}"
  if ! submit_task "$body"; then
    fail "could not submit task"
    record "$label" "FAIL" "submit error"
    return
  fi
  info "task_id: $TASK_ID"
  poll_task
}

# ════════════════════════════════════════════════════════════════════════════════
# BANNER
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${CYAN}━━ Gemma4all Full Feature Test ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo    "   Control plane : $BASE_URL"
echo    "   API key found : yes"
echo    "   Timeout/task  : ${TIMEOUT_S}s"
echo    "   Skip AppleScript: $SKIP_APPLESCRIPT"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ════════════════════════════════════════════════════════════════════════════════
# 1. HEALTH — no inference needed
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}▶  1/13 · Health check${NC}"
if [[ -n "$ONLY_SCENARIO" && "health" != "$ONLY_SCENARIO" ]]; then
  :  # skip
elif HEALTH="$(curl -fsS -m 5 "$BASE_URL/v1/tasks" \
    -H "Authorization: ApiKey $API_KEY" 2>&1)"; then
  pass "Control plane responding"
  record "Health check" "PASS" "HTTP 200"
else
  fail "Control plane not responding at $BASE_URL"
  record "Health check" "FAIL" "no response"
  echo -e "${RED}  → Is the control plane running? Try: bash scripts/start_all.sh${NC}"
  exit 1
fi

# ════════════════════════════════════════════════════════════════════════════════
# 2. PURE INFERENCE — no tools
# ════════════════════════════════════════════════════════════════════════════════
run_scenario "inference" "2/13 · Pure inference (no tools)" '{
  "schema_version":"1.0.0",
  "intent":"What is the capital of Japan? Answer in one sentence.",
  "goal":{"description":"knowledge"},
  "required_tools":[],
  "required_capabilities":["cpu_inference"],
  "complexity_hint":"light",
  "permission_level":"private_lan",
  "raw_input":"What is the capital of Japan?"
}'
if [[ -n "$TASK_ID" ]]; then
  SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
  if [[ "$STATE" == "completed" ]] && contains_ci "tokyo" "$SUMMARY"; then
    pass "Gemma 4 answered correctly: $(echo "$SUMMARY" | head -c 80)…"
    record "Pure inference" "PASS" "$SUMMARY"
  elif [[ "$STATE" == "completed" ]]; then
    fail "Completed but answer unexpected: $SUMMARY"
    record "Pure inference" "FAIL" "$SUMMARY"
  else
    fail "State=$STATE after ${ELAPSED}s"
    record "Pure inference" "FAIL" "state=$STATE"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 3. MATH VIA SHELL TOOL
# ════════════════════════════════════════════════════════════════════════════════
run_scenario "math" "3/13 · Arithmetic via shell tool" '{
  "schema_version":"1.0.0",
  "intent":"Use the shell tool to compute: 1847 multiplied by 23. Report the exact number.",
  "goal":{"description":"arithmetic"},
  "required_tools":[],
  "required_capabilities":["cpu_inference"],
  "complexity_hint":"light",
  "permission_level":"private_lan",
  "raw_input":"Use the shell tool to compute 1847 * 23"
}'
if [[ -n "$TASK_ID" ]]; then
  SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
  TOOL_CALLS="$(printf '%s' "$EVENTS" | count_events 'run.step_completed')"
  if [[ "$STATE" == "completed" ]] && contains_ci "42481" "$SUMMARY" && [[ "$TOOL_CALLS" -ge 1 ]]; then
    pass "Correct: 42481 (tool called $TOOL_CALLS time(s))"
    record "Arithmetic (shell)" "PASS" "42481"
  elif [[ "$STATE" == "completed" ]] && contains_ci "42481" "$SUMMARY"; then
    pass "Correct answer (no tool step event recorded)"
    record "Arithmetic (shell)" "PASS" "42481 but no step event"
  elif [[ "$STATE" == "completed" ]]; then
    fail "Wrong or missing answer: $SUMMARY"
    record "Arithmetic (shell)" "FAIL" "$SUMMARY"
  else
    fail "State=$STATE after ${ELAPSED}s"
    record "Arithmetic (shell)" "FAIL" "state=$STATE"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 4. SHELL COMMAND — real system info
# ════════════════════════════════════════════════════════════════════════════════
run_scenario "shell" "4/13 · Shell command (system info)" '{
  "schema_version":"1.0.0",
  "intent":"Run the shell command: uname -m  and tell me what CPU architecture this Mac uses.",
  "goal":{"description":"system"},
  "required_tools":["run_shell_command"],
  "required_capabilities":["cpu_inference"],
  "complexity_hint":"light",
  "permission_level":"private_lan",
  "raw_input":"What CPU architecture is this Mac? Run uname -m to find out."
}'
if [[ -n "$TASK_ID" ]]; then
  SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
  TOOL_CALLS="$(printf '%s' "$EVENTS" | count_events 'run.step_completed')"
  if [[ "$STATE" == "completed" ]] && \
     ( contains_ci "arm64" "$SUMMARY" || contains_ci "x86_64" "$SUMMARY" ) && \
     [[ "$TOOL_CALLS" -ge 1 ]]; then
    pass "Shell ran, architecture detected: $(echo "$SUMMARY" | head -c 80)"
    record "Shell command" "PASS" "$SUMMARY"
  elif [[ "$STATE" == "completed" ]]; then
    fail "Completed but architecture not in answer: $SUMMARY"
    record "Shell command" "FAIL" "$SUMMARY"
  else
    fail "State=$STATE after ${ELAPSED}s"
    record "Shell command" "FAIL" "state=$STATE"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 5. FILE READ — reads a temp file we create first
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}▶  5/13 · File read${NC}"
if [[ -n "$ONLY_SCENARIO" && "file_read" != "$ONLY_SCENARIO" ]]; then
  :
else
  TEST_FILE="$HOME/gemma4all_test_read_$$.txt"
  echo "The magic test word is: PINEAPPLE-DELTA-9. This file was created by the Gemma4all test suite." > "$TEST_FILE"
  info "Created test file: $TEST_FILE"

  run_scenario "file_read" "5/13 · File read" "{
    \"schema_version\":\"1.0.0\",
    \"intent\":\"Read the file at $TEST_FILE and tell me what the magic test word is.\",
    \"goal\":{\"description\":\"file read\"},
    \"required_tools\":[\"read_file\"],
    \"required_capabilities\":[\"cpu_inference\"],
    \"complexity_hint\":\"light\",
    \"permission_level\":\"private_lan\",
    \"raw_input\":\"Read $TEST_FILE and tell me the magic word\"
  }"
  rm -f "$TEST_FILE"

  if [[ -n "$TASK_ID" ]]; then
    SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
    TOOL_CALLS="$(printf '%s' "$EVENTS" | count_events 'run.step_completed')"
    if [[ "$STATE" == "completed" ]] && contains_ci "PINEAPPLE-DELTA-9" "$SUMMARY" && [[ "$TOOL_CALLS" -ge 1 ]]; then
      pass "Correct magic word found (tool called $TOOL_CALLS time(s))"
      record "File read" "PASS" "$SUMMARY"
    elif [[ "$STATE" == "completed" ]]; then
      fail "Answer missing magic word: $SUMMARY"
      record "File read" "FAIL" "$SUMMARY"
    else
      fail "State=$STATE after ${ELAPSED}s"
      record "File read" "FAIL" "state=$STATE"
    fi
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 6. FILE WRITE — write a file, then verify it exists
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}▶  6/13 · File write${NC}"
if [[ -n "$ONLY_SCENARIO" && "file_write" != "$ONLY_SCENARIO" ]]; then
  :
else
  WRITE_TARGET="$HOME/gemma4all_test_write_$$.txt"
  info "Target write path: $WRITE_TARGET"

  run_scenario "file_write" "6/13 · File write" "{
    \"schema_version\":\"1.0.0\",
    \"intent\":\"Write the text 'Hello from Gemma 4 via LiteRT' to the file $WRITE_TARGET\",
    \"goal\":{\"description\":\"file write\"},
    \"required_tools\":[\"write_file\"],
    \"required_capabilities\":[\"cpu_inference\"],
    \"complexity_hint\":\"light\",
    \"permission_level\":\"private_lan\",
    \"raw_input\":\"Write 'Hello from Gemma 4 via LiteRT' to $WRITE_TARGET\"
  }"

  if [[ -n "$TASK_ID" ]]; then
    SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
    if [[ "$STATE" == "completed" ]] && [[ -f "$WRITE_TARGET" ]]; then
      CONTENT="$(cat "$WRITE_TARGET")"
      pass "File exists on disk. Content: $(echo "$CONTENT" | head -c 60)"
      record "File write" "PASS" "$CONTENT"
      rm -f "$WRITE_TARGET"
    elif [[ "$STATE" == "completed" ]]; then
      fail "Task completed but file not found at $WRITE_TARGET"
      record "File write" "FAIL" "file not created"
    else
      fail "State=$STATE after ${ELAPSED}s"
      record "File write" "FAIL" "state=$STATE"
    fi
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 7. TRANSLATION
# ════════════════════════════════════════════════════════════════════════════════
run_scenario "translate" "7/13 · Translation (EN → ZH)" '{
  "schema_version":"1.0.0",
  "intent":"Translate to Chinese: The Gemma model runs entirely on my local Mac.",
  "goal":{"description":"translation"},
  "required_tools":[],
  "required_capabilities":["cpu_inference"],
  "complexity_hint":"light",
  "permission_level":"private_lan",
  "raw_input":"Translate to Chinese: The Gemma model runs entirely on my local Mac."
}'
if [[ -n "$TASK_ID" ]]; then
  SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
  HAS_ZH="$(python3 -c "import sys,re; print('yes' if re.search(r'[一-鿿]', sys.argv[1]) else 'no')" "$SUMMARY")"
  if [[ "$STATE" == "completed" ]] && [[ "$HAS_ZH" == "yes" ]]; then
    pass "Contains Chinese characters: $(echo "$SUMMARY" | head -c 60)"
    record "Translation EN→ZH" "PASS" "$SUMMARY"
  elif [[ "$STATE" == "completed" ]]; then
    fail "Completed but no Chinese output: $SUMMARY"
    record "Translation EN→ZH" "FAIL" "$SUMMARY"
  else
    fail "State=$STATE after ${ELAPSED}s"
    record "Translation EN→ZH" "FAIL" "state=$STATE"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 8. WEB FETCH
# ════════════════════════════════════════════════════════════════════════════════
run_scenario "web_fetch" "8/13 · Web fetch (httpbin.org)" '{
  "schema_version":"1.0.0",
  "intent":"Fetch https://httpbin.org/json and tell me what the slideshow title is.",
  "goal":{"description":"web fetch"},
  "required_tools":["web_fetch"],
  "required_capabilities":["cpu_inference"],
  "complexity_hint":"light",
  "permission_level":"private_lan",
  "raw_input":"Fetch https://httpbin.org/json and tell me the slideshow title"
}'
if [[ -n "$TASK_ID" ]]; then
  SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
  TOOL_CALLS="$(printf '%s' "$EVENTS" | count_events 'run.step_completed')"
  if [[ "$STATE" == "completed" ]] && contains_ci "sample slide show" "$SUMMARY" && [[ "$TOOL_CALLS" -ge 1 ]]; then
    pass "Fetched and extracted correctly (tool called $TOOL_CALLS time(s))"
    record "Web fetch" "PASS" "$SUMMARY"
  elif [[ "$STATE" == "completed" ]]; then
    fail "Completed but wrong answer: $SUMMARY"
    record "Web fetch" "FAIL" "$SUMMARY"
  else
    fail "State=$STATE after ${ELAPSED}s"
    record "Web fetch" "FAIL" "state=$STATE"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 9. WEB SEARCH (DuckDuckGo)
# ════════════════════════════════════════════════════════════════════════════════
run_scenario "web_search" "9/13 · Web search (DuckDuckGo)" '{
  "schema_version":"1.0.0",
  "intent":"Search the web for: LiteRT on-device AI inference and give me the top result title.",
  "goal":{"description":"search"},
  "required_tools":["web_search"],
  "required_capabilities":["cpu_inference"],
  "complexity_hint":"light",
  "permission_level":"private_lan",
  "raw_input":"Search for: LiteRT on-device AI inference"
}'
if [[ -n "$TASK_ID" ]]; then
  SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
  TOOL_CALLS="$(printf '%s' "$EVENTS" | count_events 'run.step_completed')"
  if [[ "$STATE" == "completed" ]] && [[ "$TOOL_CALLS" -ge 1 ]] && [[ ${#SUMMARY} -gt 20 ]]; then
    pass "Search ran, got result: $(echo "$SUMMARY" | head -c 80)…"
    record "Web search" "PASS" "$SUMMARY"
  elif [[ "$STATE" == "completed" ]]; then
    fail "Completed but short/empty result: $SUMMARY"
    record "Web search" "FAIL" "$SUMMARY"
  else
    fail "State=$STATE after ${ELAPSED}s"
    record "Web search" "FAIL" "state=$STATE"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 10. APPLESCRIPT — Create Calendar event
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}▶  10/13 · AppleScript — Calendar event${NC}"
if [[ "$SKIP_APPLESCRIPT" == "true" ]]; then
  skip "Skipped via --skip-applescript"
  record "AppleScript (Calendar)" "SKIP" "user requested skip"
elif [[ -n "$ONLY_SCENARIO" && "applescript" != "$ONLY_SCENARIO" ]]; then
  :
elif [[ "$(uname -s)" != "Darwin" ]]; then
  skip "Not macOS — AppleScript unavailable"
  record "AppleScript (Calendar)" "SKIP" "not macOS"
else
  EVENT_TITLE="GemmaTest-$$"
  run_scenario "applescript" "10/13 · AppleScript (Calendar)" "{
    \"schema_version\":\"1.0.0\",
    \"intent\":\"Create a calendar event called '$EVENT_TITLE' for tomorrow at 10am using AppleScript.\",
    \"goal\":{\"description\":\"calendar\"},
    \"required_tools\":[\"run_applescript\"],
    \"required_capabilities\":[\"cpu_inference\"],
    \"complexity_hint\":\"light\",
    \"permission_level\":\"private_lan\",
    \"raw_input\":\"Create a calendar event called $EVENT_TITLE for tomorrow at 10am\"
  }"

  if [[ -n "$TASK_ID" ]]; then
    SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
    TOOL_CALLS="$(printf '%s' "$EVENTS" | count_events 'run.step_completed')"
    if [[ "$STATE" == "completed" ]] && [[ "$TOOL_CALLS" -ge 1 ]]; then
      pass "AppleScript ran (tool called $TOOL_CALLS time(s)) — check Calendar app for '$EVENT_TITLE'"
      info "  → Open Calendar.app and confirm event exists for tomorrow at 10am"
      record "AppleScript (Calendar)" "PASS" "event=$EVENT_TITLE"
    elif [[ "$STATE" == "completed" ]]; then
      fail "Completed but no tool call recorded: $SUMMARY"
      record "AppleScript (Calendar)" "FAIL" "$SUMMARY"
    else
      fail "State=$STATE after ${ELAPSED}s — $SUMMARY"
      record "AppleScript (Calendar)" "FAIL" "state=$STATE"
    fi
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 11. SCREENSHOT
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}▶  11/13 · Screenshot${NC}"
if [[ -n "$ONLY_SCENARIO" && "screenshot" != "$ONLY_SCENARIO" ]]; then
  :
elif [[ "$(uname -s)" != "Darwin" ]]; then
  skip "Not macOS — screencapture unavailable"
  record "Screenshot" "SKIP" "not macOS"
else
  run_scenario "screenshot" "11/13 · Screenshot" '{
    "schema_version":"1.0.0",
    "intent":"Take a screenshot of the desktop and tell me approximately what is visible on screen.",
    "goal":{"description":"screenshot"},
    "required_tools":["take_screenshot"],
    "required_capabilities":["cpu_inference"],
    "complexity_hint":"light",
    "permission_level":"private_lan",
    "raw_input":"Take a screenshot and describe what you see"
  }'

  if [[ -n "$TASK_ID" ]]; then
    SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
    TOOL_CALLS="$(printf '%s' "$EVENTS" | count_events 'run.step_completed')"
    SCREENSHOT_PATH="/tmp/gemma4all_screenshot.png"
    if [[ "$STATE" == "completed" ]] && [[ "$TOOL_CALLS" -ge 1 ]] && [[ -f "$SCREENSHOT_PATH" ]]; then
      FSIZE="$(python3 -c "import os; print(os.path.getsize('$SCREENSHOT_PATH'))")"
      pass "Screenshot taken (${FSIZE} bytes at $SCREENSHOT_PATH)"
      info "  Gemma says: $(echo "$SUMMARY" | head -c 100)…"
      record "Screenshot" "PASS" "$SUMMARY"
    elif [[ "$STATE" == "completed" ]] && [[ "$TOOL_CALLS" -ge 1 ]]; then
      pass "Tool ran — screenshot file may be at $SCREENSHOT_PATH"
      info "  Gemma says: $(echo "$SUMMARY" | head -c 100)"
      record "Screenshot" "PASS" "$SUMMARY"
    elif [[ "$STATE" == "completed" ]]; then
      fail "Completed but no tool call: $SUMMARY"
      record "Screenshot" "FAIL" "$SUMMARY"
    else
      fail "State=$STATE after ${ELAPSED}s"
      record "Screenshot" "FAIL" "state=$STATE"
    fi
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 12. MULTI-STEP — read file → summarise → run shell command (3 steps, 1 task)
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}▶  12/13 · Multi-step (file → summary → shell)${NC}"
if [[ -n "$ONLY_SCENARIO" && "multistep" != "$ONLY_SCENARIO" ]]; then
  :
else
  MS_FILE="$HOME/gemma4all_multistep_$$.txt"
  cat > "$MS_FILE" <<'EOF'
Project: Gemma4all
Status: Phase 3 complete
Priority tools: file read, shell, web fetch, AppleScript
Next step: record demo video
EOF
  info "Created multi-step test file: $MS_FILE"

  run_scenario "multistep" "12/13 · Multi-step" "{
    \"schema_version\":\"1.0.0\",
    \"intent\":\"Read the file $MS_FILE, summarise it in one sentence, then use the shell to echo the word DONE.\",
    \"goal\":{\"description\":\"multi-step\"},
    \"required_tools\":[\"read_file\",\"run_shell_command\"],
    \"required_capabilities\":[\"cpu_inference\"],
    \"complexity_hint\":\"moderate\",
    \"permission_level\":\"private_lan\",
    \"raw_input\":\"Read $MS_FILE, summarise it, then run: echo DONE\"
  }"
  rm -f "$MS_FILE"

  if [[ -n "$TASK_ID" ]]; then
    SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
    TOOL_CALLS="$(printf '%s' "$EVENTS" | count_events 'run.step_completed')"
    if [[ "$STATE" == "completed" ]] && [[ "$TOOL_CALLS" -ge 2 ]]; then
      pass "Multi-step completed with $TOOL_CALLS tool calls"
      info "  Summary: $(echo "$SUMMARY" | head -c 100)"
      record "Multi-step (file+shell)" "PASS" "steps=$TOOL_CALLS"
    elif [[ "$STATE" == "completed" ]] && [[ "$TOOL_CALLS" -eq 1 ]]; then
      fail "Only 1 tool call (expected ≥2): $SUMMARY"
      record "Multi-step (file+shell)" "FAIL" "only $TOOL_CALLS step(s)"
    elif [[ "$STATE" == "completed" ]]; then
      fail "Completed with no tool calls: $SUMMARY"
      record "Multi-step (file+shell)" "FAIL" "no steps"
    else
      fail "State=$STATE after ${ELAPSED}s"
      record "Multi-step (file+shell)" "FAIL" "state=$STATE"
    fi
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# 13. MEMORY — two sequential tasks, second asks about the first
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}▶  13/13 · Memory (sequential context)${NC}"
if [[ -n "$ONLY_SCENARIO" && "memory" != "$ONLY_SCENARIO" ]]; then
  :
else
  UNIQ_WORD="QUASAR-$(date +%s)"
  info "Unique word for memory test: $UNIQ_WORD"

  # Task A: tell Gemma a fact
  run_scenario "memory_a" "13a · Memory — store fact" "{
    \"schema_version\":\"1.0.0\",
    \"intent\":\"Remember this: the project secret word is $UNIQ_WORD. Acknowledge you have noted it.\",
    \"goal\":{\"description\":\"memory\"},
    \"required_tools\":[],
    \"required_capabilities\":[\"cpu_inference\"],
    \"complexity_hint\":\"light\",
    \"permission_level\":\"private_lan\",
    \"raw_input\":\"Remember: the secret word is $UNIQ_WORD\"
  }"
  TASK_A_STATE="$STATE"

  # Task B: ask Gemma to recall (memory context is passed via MemoryStore)
  run_scenario "memory_b" "13b · Memory — recall fact" '{
    "schema_version":"1.0.0",
    "intent":"What was the project secret word I mentioned recently?",
    "goal":{"description":"memory recall"},
    "required_tools":[],
    "required_capabilities":["cpu_inference"],
    "complexity_hint":"light",
    "permission_level":"private_lan",
    "raw_input":"What was the secret word I just told you?"
  }'

  if [[ -n "$TASK_ID" ]]; then
    SUMMARY_B="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | get_summary)"
    if [[ "$TASK_A_STATE" == "completed" && "$STATE" == "completed" ]] && \
       contains_ci "$UNIQ_WORD" "$SUMMARY_B"; then
      pass "Memory works — recalled: $UNIQ_WORD"
      record "Memory (sequential)" "PASS" "$SUMMARY_B"
    elif [[ "$STATE" == "completed" ]]; then
      fail "Did not recall the word '$UNIQ_WORD': $SUMMARY_B"
      info "  (Memory is a best-effort short summary, not guaranteed recall)"
      record "Memory (sequential)" "FAIL" "word not recalled"
    else
      fail "State=$STATE after ${ELAPSED}s"
      record "Memory (sequential)" "FAIL" "state=$STATE"
    fi
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY TABLE
# ════════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${CYAN}━━ Results ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "  %-30s  %s\n" "Scenario" "Result"
printf "  %-30s  %s\n" "──────────────────────────────" "──────"
for i in "${!RESULTS_NAME[@]}"; do
  case "${RESULTS_VERDICT[$i]}" in
    PASS) colour="$GREEN" ;;
    FAIL) colour="$RED"   ;;
    *)    colour="$YELLOW";;
  esac
  printf "  %-30s  ${colour}%s${NC}  %s\n" \
    "${RESULTS_NAME[$i]}" "${RESULTS_VERDICT[$i]}" \
    "$(echo "${RESULTS_DETAIL[$i]}" | head -c 50)"
done
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}PASS: $total_pass${NC}  ${RED}FAIL: $total_fail${NC}  ${YELLOW}SKIP: $total_skip${NC}"
echo ""

if [[ $total_fail -eq 0 && $total_pass -gt 0 ]]; then
  echo -e "${GREEN}${BOLD}  ✓ All tests passed. System is fully operational.${NC}"
elif [[ $total_fail -gt 0 ]]; then
  echo -e "${RED}${BOLD}  ✗ $total_fail test(s) failed. Check output above for details.${NC}"
fi
echo ""

exit $([[ $total_fail -eq 0 ]] && echo 0 || echo 1)
