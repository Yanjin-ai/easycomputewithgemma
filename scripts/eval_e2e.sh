#!/usr/bin/env bash
# Gemma4all — Comprehensive E2E Evaluation Script
#
# Runs 5 task-scenario categories against a live control plane + desktop runtime.
# Each scenario has a pass/fail verdict and a quality score (0-3).
#
# Usage:
#   bash scripts/eval_e2e.sh [--url http://localhost:3000] [--timeout 180] [--scenario SCENARIO]
#
# Scenarios (use with --scenario to run one only):
#   quick         Simple arithmetic — sanity check
#   tool          Shell tool call — verifies tool dispatch
#   file          File read/write — verifies filesystem tools
#   translate     Translation — verifies multilingual output
#   web           Web fetch + summarise — verifies web_fetch tool
#
# Output: coloured terminal report + eval_results_<timestamp>.json

set -euo pipefail

BASE_URL="http://localhost:3000"
TIMEOUT_S=180
ONLY_SCENARIO=""
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      [[ $# -ge 2 ]] || { echo "error: --url requires a value" >&2; exit 1; }
      BASE_URL="${2%/}"; shift 2 ;;
    --timeout)
      [[ $# -ge 2 ]] || { echo "error: --timeout requires a value" >&2; exit 1; }
      TIMEOUT_S="$2"; shift 2 ;;
    --scenario)
      [[ $# -ge 2 ]] || { echo "error: --scenario requires a value" >&2; exit 1; }
      ONLY_SCENARIO="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── colours ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

need() { command -v "$1" >/dev/null || { echo "error: $1 not found" >&2; exit 1; }; }
need curl
need python3

# ── API key ────────────────────────────────────────────────────────────────────
API_KEY=""
API_KEY_FILE=""
for _path in \
  "$REPO_ROOT/services/desktop-runtime/.desktop_api_key" \
  "$REPO_ROOT/services/control-plane/.desktop_api_key" \
  "${API_KEY_PATH:-}"; do
  [[ -n "$_path" && -f "$_path" ]] || continue
  API_KEY="$(python3 -c 'import sys; print(open(sys.argv[1]).read().strip())' "$_path")"
  [[ -n "$API_KEY" ]] || continue
  API_KEY_FILE="$_path"
  break
done
[[ -n "$API_KEY" ]] || { echo "error: API key not found." >&2; exit 1; }

# ── python helpers ─────────────────────────────────────────────────────────────
json_get() {
  python3 -c '
import json,sys
data=json.load(sys.stdin)
v=eval(sys.argv[1], {"__builtins__": {}}, {"data": data})
print("" if v is None else json.dumps(v) if isinstance(v, (dict,list)) else v)
' "$1"
}

event_payload() {
  python3 -c '
import json,sys
data=json.load(sys.stdin)
events=data.get("events", data if isinstance(data,list) else [])
want=sys.argv[1].split(",")
for et in want:
  for ev in reversed(events):
    if ev.get("event_type")==et:
      print(json.dumps(ev.get("payload",{}), ensure_ascii=False))
      raise SystemExit
print("{}")
' "$1"
}

event_summary() {
  python3 -c '
import json,sys
payload=json.loads(sys.stdin.read() or "{}")
print(payload.get("summary") or payload.get("result") or json.dumps(payload, ensure_ascii=False))
'
}

event_count() {
  python3 -c '
import json,sys
data=json.load(sys.stdin)
events=data.get("events", data if isinstance(data,list) else [])
print(sum(1 for e in events if e.get("event_type")==sys.argv[1]))
' "$1"
}

contains_ci() {
  # case-insensitive substring check
  python3 -c '
import sys
text=sys.argv[1].lower()
needle=sys.argv[2].lower()
sys.exit(0 if needle in text else 1)
' "$1" "$2"
}

# ── core task runner ────────────────────────────────────────────────────────────
TASK_ID=""
STATE=""
ELAPSED=0
EVENTS=""

submit_task() {
  local body="$1"
  local resp
  if ! resp="$(curl -fsS -X POST "$BASE_URL/v1/tasks" \
    -H "Authorization: ApiKey $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$body")"; then
    echo "error: submit failed" >&2; return 1
  fi
  TASK_ID="$(printf '%s' "$resp" | json_get 'data.get("task_id") or data.get("task",{}).get("task_id")')"
  [[ -n "$TASK_ID" ]] || { echo "error: no task_id in response: $resp" >&2; return 1; }
}

poll_task() {
  STATE=""; ELAPSED=0
  while [[ $ELAPSED -le $TIMEOUT_S ]]; do
    local resp
    resp="$(curl -fsS "$BASE_URL/v1/tasks/$TASK_ID" -H "Authorization: ApiKey $API_KEY")"
    STATE="$(printf '%s' "$resp" | json_get 'data.get("current_state") or data.get("state")')"
    [[ "$STATE" == "completed" || "$STATE" == "failed" || "$STATE" == "cancelled" ]] && return 0
    [[ $ELAPSED -ge $TIMEOUT_S ]] && return 0
    sleep 5
    ELAPSED=$((ELAPSED + 5))
  done
}

fetch_events() {
  EVENTS="$(curl -fsS "$BASE_URL/v1/tasks/$TASK_ID/events?limit=100" \
    -H "Authorization: ApiKey $API_KEY")"
}

# ── result accumulator ─────────────────────────────────────────────────────────
TOTAL=0
PASSED=0
FAILED=0
SCORE_SUM=0
RESULTS_JSON="[]"

record_result() {
  local name="$1" verdict="$2" score="$3" summary="$4" reason="$5"
  TOTAL=$((TOTAL + 1))
  SCORE_SUM=$((SCORE_SUM + score))
  if [[ "$verdict" == "PASS" ]]; then
    PASSED=$((PASSED + 1))
    echo -e "${GREEN}✓ PASS${NC}  [${score}/3]  ${BOLD}${name}${NC}"
  else
    FAILED=$((FAILED + 1))
    echo -e "${RED}✗ FAIL${NC}  [${score}/3]  ${BOLD}${name}${NC}"
    [[ -n "$reason" ]] && echo -e "         reason: ${YELLOW}${reason}${NC}"
  fi
  [[ -n "$summary" ]] && echo -e "         answer: $(printf '%s' "$summary" | head -c 200)"
  echo ""

  RESULTS_JSON="$(python3 -c "
import json, sys
arr = json.loads(sys.argv[1])
arr.append({
  'scenario': sys.argv[2],
  'verdict': sys.argv[3],
  'score': int(sys.argv[4]),
  'summary': sys.argv[5],
  'reason': sys.argv[6],
  'task_id': sys.argv[7],
  'elapsed_s': int(sys.argv[8]),
})
print(json.dumps(arr, ensure_ascii=False, indent=2))
" "$RESULTS_JSON" "$name" "$verdict" "$score" "$summary" "$reason" "${TASK_ID:-}" "$ELAPSED")"
}

# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO DEFINITIONS
# ══════════════════════════════════════════════════════════════════════════════

# ── 1. Quick arithmetic (sanity check) ─────────────────────────────────────────
run_quick() {
  echo -e "${CYAN}▶  Scenario 1/5: Quick arithmetic${NC}"
  local body='{
    "schema_version":"1.0.0",
    "intent":"What is 7 times 8?",
    "goal":{"description":"arithmetic"},
    "required_tools":[],
    "required_capabilities":["cpu_inference"],
    "complexity_hint":"light",
    "permission_level":"private_lan",
    "raw_input":"What is 7 times 8?"
  }'
  submit_task "$body"
  echo "  task_id: $TASK_ID"
  poll_task
  fetch_events

  local summary reason score verdict
  summary="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | event_summary)"
  reason="$(printf '%s' "$EVENTS" | event_payload 'route.failed,run.failed' | event_summary)"

  if [[ "$STATE" == "completed" ]] && (contains_ci "$summary" "56" || contains_ci "$summary" "56."); then
    score=3; verdict="PASS"
  elif [[ "$STATE" == "completed" ]]; then
    score=1; verdict="FAIL"; reason="wrong answer (expected 56)"
  else
    score=0; verdict="FAIL"; reason="state=${STATE:-timeout} after ${ELAPSED}s"
  fi
  record_result "Quick arithmetic (7×8=56)" "$verdict" "$score" "$summary" "$reason"
}

# ── 2. Shell tool call ──────────────────────────────────────────────────────────
run_tool() {
  echo -e "${CYAN}▶  Scenario 2/5: Shell tool call${NC}"
  local body='{
    "schema_version":"1.0.0",
    "intent":"Use the shell_eval tool to compute: 123 * 456",
    "goal":{"description":"arithmetic via tool"},
    "required_tools":[],
    "required_capabilities":["cpu_inference"],
    "complexity_hint":"light",
    "permission_level":"private_lan",
    "raw_input":"Use the shell_eval tool to compute: 123 * 456"
  }'
  submit_task "$body"
  echo "  task_id: $TASK_ID"
  poll_task
  fetch_events

  local summary reason score verdict tool_calls
  summary="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | event_summary)"
  reason="$(printf '%s' "$EVENTS" | event_payload 'route.failed,run.failed' | event_summary)"
  tool_calls="$(printf '%s' "$EVENTS" | event_count 'run.step_completed')"

  if [[ "$STATE" == "completed" ]] && contains_ci "$summary" "56088" && [[ "$tool_calls" -ge 1 ]]; then
    score=3; verdict="PASS"
  elif [[ "$STATE" == "completed" ]] && contains_ci "$summary" "56088"; then
    score=2; verdict="PASS"; reason="correct but no tool event recorded"
  elif [[ "$STATE" == "completed" ]]; then
    score=1; verdict="FAIL"; reason="wrong answer or tool not called (tool_calls=${tool_calls})"
  else
    score=0; verdict="FAIL"; reason="state=${STATE:-timeout} after ${ELAPSED}s"
  fi
  record_result "Shell tool (123×456=56088)" "$verdict" "$score" "$summary" "$reason"
}

# ── 3. File read/write ──────────────────────────────────────────────────────────
run_file() {
  echo -e "${CYAN}▶  Scenario 3/5: File read/write${NC}"

  # Create a temp file with known content the model can read
  local tmpfile
  tmpfile="$(mktemp "$HOME/gemma4all_eval_XXXXXX.txt")"
  echo "The secret code is: ALPHA-7742" > "$tmpfile"
  local fname
  fname="$(basename "$tmpfile")"

  local body
  body="$(python3 -c "
import json, sys
task = {
  'schema_version': '1.0.0',
  'intent': f'Read the file at {sys.argv[1]} and tell me what the secret code is.',
  'goal': {'description': 'file read'},
  'required_tools': ['read_file'],
  'required_capabilities': ['cpu_inference'],
  'complexity_hint': 'light',
  'permission_level': 'private_lan',
  'raw_input': f'Read the file at {sys.argv[1]} and tell me what the secret code is.',
}
print(json.dumps(task))
" "$tmpfile")"

  submit_task "$body"
  echo "  task_id: $TASK_ID  (reading $tmpfile)"
  poll_task
  fetch_events
  rm -f "$tmpfile"

  local summary reason score verdict tool_calls
  summary="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | event_summary)"
  reason="$(printf '%s' "$EVENTS" | event_payload 'route.failed,run.failed' | event_summary)"
  tool_calls="$(printf '%s' "$EVENTS" | event_count 'run.step_completed')"

  if [[ "$STATE" == "completed" ]] && contains_ci "$summary" "ALPHA-7742" && [[ "$tool_calls" -ge 1 ]]; then
    score=3; verdict="PASS"
  elif [[ "$STATE" == "completed" ]] && contains_ci "$summary" "ALPHA-7742"; then
    score=2; verdict="PASS"; reason="correct but tool event missing"
  elif [[ "$STATE" == "completed" ]]; then
    score=1; verdict="FAIL"; reason="answer missing ALPHA-7742 (tool_calls=${tool_calls})"
  else
    score=0; verdict="FAIL"; reason="state=${STATE:-timeout} after ${ELAPSED}s"
  fi
  record_result "File read (secret code)" "$verdict" "$score" "$summary" "$reason"
}

# ── 4. Translation ──────────────────────────────────────────────────────────────
run_translate() {
  echo -e "${CYAN}▶  Scenario 4/5: Translation (EN→ZH)${NC}"
  local body='{
    "schema_version":"1.0.0",
    "intent":"Translate this sentence to Chinese: The weather is beautiful today.",
    "goal":{"description":"translation"},
    "required_tools":[],
    "required_capabilities":["cpu_inference"],
    "complexity_hint":"light",
    "permission_level":"private_lan",
    "raw_input":"Translate this sentence to Chinese: The weather is beautiful today."
  }'
  submit_task "$body"
  echo "  task_id: $TASK_ID"
  poll_task
  fetch_events

  local summary reason score verdict
  summary="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | event_summary)"
  reason="$(printf '%s' "$EVENTS" | event_payload 'route.failed,run.failed' | event_summary)"

  # Check for common Chinese characters that would appear in this translation
  local has_chinese
  has_chinese="$(python3 -c "
import sys, re
text = sys.argv[1]
# Any CJK unified ideograph
has_cjk = bool(re.search(r'[一-鿿]', text))
print('yes' if has_cjk else 'no')
" "$summary")"

  # Also check for key weather-related Chinese words (天气/今天/美丽/漂亮)
  local has_key_word
  has_key_word="$(python3 -c "
import sys
text = sys.argv[1]
keywords = ['天气', '今天', '美丽', '漂亮', '好', '晴']
print('yes' if any(k in text for k in keywords) else 'no')
" "$summary")"

  if [[ "$STATE" == "completed" && "$has_chinese" == "yes" && "$has_key_word" == "yes" ]]; then
    score=3; verdict="PASS"
  elif [[ "$STATE" == "completed" && "$has_chinese" == "yes" ]]; then
    score=2; verdict="PASS"; reason="Chinese output but key words not detected"
  elif [[ "$STATE" == "completed" ]]; then
    score=1; verdict="FAIL"; reason="no Chinese characters in output"
  else
    score=0; verdict="FAIL"; reason="state=${STATE:-timeout} after ${ELAPSED}s"
  fi
  record_result "Translation (EN→ZH weather)" "$verdict" "$score" "$summary" "$reason"
}

# ── 5. Web fetch + summarise ────────────────────────────────────────────────────
run_web() {
  echo -e "${CYAN}▶  Scenario 5/5: Web fetch + summarise${NC}"
  local body='{
    "schema_version":"1.0.0",
    "intent":"Fetch https://httpbin.org/json and tell me what the slideshow title is.",
    "goal":{"description":"web fetch"},
    "required_tools":["web_fetch"],
    "required_capabilities":["cpu_inference"],
    "complexity_hint":"light",
    "permission_level":"private_lan",
    "raw_input":"Fetch https://httpbin.org/json and tell me what the slideshow title is."
  }'
  submit_task "$body"
  echo "  task_id: $TASK_ID"
  poll_task
  fetch_events

  local summary reason score verdict tool_calls
  summary="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | event_summary)"
  reason="$(printf '%s' "$EVENTS" | event_payload 'route.failed,run.failed' | event_summary)"
  tool_calls="$(printf '%s' "$EVENTS" | event_count 'run.step_completed')"

  # httpbin.org/json returns {"slideshow": {"title": "Sample Slide Show", ...}}
  if [[ "$STATE" == "completed" ]] && contains_ci "$summary" "sample slide show" && [[ "$tool_calls" -ge 1 ]]; then
    score=3; verdict="PASS"
  elif [[ "$STATE" == "completed" ]] && contains_ci "$summary" "sample slide show"; then
    score=2; verdict="PASS"; reason="correct but tool event missing"
  elif [[ "$STATE" == "completed" ]] && [[ "$tool_calls" -ge 1 ]]; then
    score=1; verdict="FAIL"; reason="tool was called but wrong/incomplete answer"
  else
    score=0; verdict="FAIL"; reason="state=${STATE:-timeout} after ${ELAPSED}s"
  fi
  record_result "Web fetch (httpbin.org/json)" "$verdict" "$score" "$summary" "$reason"
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}${CYAN}━━ Gemma4all E2E Evaluation ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "   Control plane : $BASE_URL"
echo "   API key file  : $API_KEY_FILE"
echo "   Timeout/task  : ${TIMEOUT_S}s"
echo "   Scenario filter: ${ONLY_SCENARIO:-all}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Verify control plane is reachable
if ! curl -fsS -o /dev/null -m 5 "$BASE_URL/v1/tasks" \
    -H "Authorization: ApiKey $API_KEY" 2>/dev/null; then
  echo -e "${RED}error: control plane not reachable at $BASE_URL${NC}" >&2
  echo "  Start with: bash scripts/start_all.sh" >&2
  exit 1
fi

case "${ONLY_SCENARIO:-all}" in
  quick)     run_quick ;;
  tool)      run_tool ;;
  file)      run_file ;;
  translate) run_translate ;;
  web)       run_web ;;
  all)
    run_quick
    run_tool
    run_file
    run_translate
    run_web
    ;;
  *) echo "error: unknown scenario '$ONLY_SCENARIO'" >&2; exit 1 ;;
esac

# ── Summary ────────────────────────────────────────────────────────────────────
MAX_SCORE=$((TOTAL * 3))
PCT=0
[[ $MAX_SCORE -gt 0 ]] && PCT=$(( (SCORE_SUM * 100) / MAX_SCORE ))

echo -e "${BOLD}${CYAN}━━ Results ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "   Scenarios  : ${TOTAL}"
echo -e "   Passed     : ${GREEN}${PASSED}${NC}"
echo -e "   Failed     : ${RED}${FAILED}${NC}"
echo -e "   Quality    : ${SCORE_SUM}/${MAX_SCORE}  (${PCT}%)"

if [[ $PASSED -eq $TOTAL ]]; then
  echo -e "   ${GREEN}${BOLD}ALL PASS ✓${NC}"
elif [[ $PASSED -gt 0 ]]; then
  echo -e "   ${YELLOW}PARTIAL — review failures above${NC}"
else
  echo -e "   ${RED}ALL FAILED — check runtime logs${NC}"
fi
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ── Write JSON report ──────────────────────────────────────────────────────────
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_PATH="$REPO_ROOT/eval_results_${TIMESTAMP}.json"
python3 -c "
import json, sys, datetime
results = json.loads(sys.argv[1])
report = {
  'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
  'control_plane': sys.argv[2],
  'total': int(sys.argv[3]),
  'passed': int(sys.argv[4]),
  'failed': int(sys.argv[5]),
  'quality_score': int(sys.argv[6]),
  'max_quality_score': int(sys.argv[7]),
  'quality_pct': int(sys.argv[8]),
  'scenarios': results,
}
print(json.dumps(report, ensure_ascii=False, indent=2))
" "$RESULTS_JSON" "$BASE_URL" "$TOTAL" "$PASSED" "$FAILED" "$SCORE_SUM" "$MAX_SCORE" "$PCT" \
  > "$REPORT_PATH"

echo ""
echo "  JSON report : $REPORT_PATH"
echo ""

[[ $FAILED -eq 0 ]]
