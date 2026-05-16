#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://localhost:3000"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="quick"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)
      MODE="quick"
      shift
      ;;
    --tool-test)
      MODE="tool"
      shift
      ;;
    --url)
      [[ $# -ge 2 ]] || { echo "error: --url requires a value" >&2; exit 1; }
      BASE_URL="${2%/}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--quick|--tool-test] [--url http://localhost:3000]"
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

need() { command -v "$1" >/dev/null || { echo "error: $1 not found" >&2; exit 1; }; }
need curl
need python3

read_key() {
  local path
  for path in \
    "$REPO_ROOT/services/desktop-runtime/.desktop_api_key" \
    "$REPO_ROOT/services/control-plane/.desktop_api_key" \
    "${API_KEY_PATH:-}"; do
    [[ -n "$path" && -f "$path" ]] || continue
    API_KEY="$(python3 -c 'import sys; print(open(sys.argv[1]).read().strip())' "$path")"
    [[ -n "$API_KEY" ]] || continue
    API_KEY_FILE="$path"
    return 0
  done
  echo "error: API key not found. Expected services/desktop-runtime/.desktop_api_key, services/control-plane/.desktop_api_key, or API_KEY_PATH." >&2
  exit 1
}

json_get() {
  python3 -c 'import json,sys
data=json.load(sys.stdin)
v=eval(sys.argv[1], {"__builtins__": {}}, {"data": data})
print("" if v is None else json.dumps(v) if isinstance(v, (dict, list)) else v)' "$1"
}

event_payload() {
  python3 -c 'import json,sys
data=json.load(sys.stdin)
events=data.get("events", data if isinstance(data, list) else [])
want=sys.argv[1].split(",")
for event_type in want:
  for event in reversed(events):
    if event.get("event_type") == event_type:
      print(json.dumps(event.get("payload", {}), ensure_ascii=False))
      raise SystemExit
print("{}")' "$1"
}

event_summary() {
  python3 -c 'import json,sys
payload=json.loads(sys.stdin.read() or "{}")
print(payload.get("summary") or payload.get("result") or json.dumps(payload, ensure_ascii=False))'
}

event_count() {
  python3 -c 'import json,sys
data=json.load(sys.stdin)
events=data.get("events", data if isinstance(data, list) else [])
print(sum(1 for event in events if event.get("event_type") == sys.argv[1]))' "$1"
}

submit_task() {
  local task_body="$1"
  if ! CREATE_RESP="$(curl -fsS -X POST "$BASE_URL/v1/tasks" \
    -H "Authorization: ApiKey $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$task_body")"; then
    echo "error: failed to submit task" >&2
    exit 1
  fi

  TASK_ID="$(printf '%s' "$CREATE_RESP" | json_get 'data.get("task_id") or data.get("task", {}).get("task_id")')"
  [[ -n "$TASK_ID" ]] || { echo "error: task_id missing from response: $CREATE_RESP" >&2; exit 1; }
  echo "Submitted task: $TASK_ID"
}

poll_task() {
  STATE=""
  RUNTIME=""
  ELAPSED=0
  while [[ $ELAPSED -le 120 ]]; do
    if ! TASK_RESP="$(curl -fsS "$BASE_URL/v1/tasks/$TASK_ID" -H "Authorization: ApiKey $API_KEY")"; then
      echo "error: failed to fetch task $TASK_ID" >&2
      exit 1
    fi
    STATE="$(printf '%s' "$TASK_RESP" | json_get 'data.get("current_state") or data.get("state")')"
    RUNTIME="$(printf '%s' "$TASK_RESP" | json_get 'data.get("current_runtime") or data.get("runtime") or ""')"
    echo "[${ELAPSED}s] state=${STATE:-unknown} runtime=${RUNTIME:-unknown}"
    [[ "$STATE" == "completed" || "$STATE" == "failed" || "$STATE" == "cancelled" ]] && break
    [[ $ELAPSED -eq 120 ]] && break
    sleep 3
    ELAPSED=$((ELAPSED + 3))
  done
}

fetch_events() {
  EVENTS="$(curl -fsS "$BASE_URL/v1/tasks/$TASK_ID/events?limit=50" -H "Authorization: ApiKey $API_KEY")"
}

run_quick_test() {
  local task_body='{
    "schema_version": "1.0.0",
    "intent": "What is 7 times 8?",
    "goal": {"description": "arithmetic"},
    "required_tools": [],
    "required_capabilities": ["cpu_inference"],
    "complexity_hint": "light",
    "permission_level": "private_lan",
    "raw_input": "What is 7 times 8?"
  }'

  submit_task "$task_body"
  poll_task
  fetch_events

  if [[ "$STATE" == "completed" ]]; then
    SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | event_summary)"
    echo "✓ PASS — Task completed in ${ELAPSED}s"
    echo "Answer: $SUMMARY"
    exit 0
  fi

  REASON="$(printf '%s' "$EVENTS" | event_payload 'route.failed,run.failed')"
  echo "✗ FAIL — Task ${STATE:-timed out} after ${ELAPSED}s"
  echo "Reason: $REASON"
  exit 1
}

run_tool_test() {
  local task_body='{
    "schema_version": "1.0.0",
    "intent": "Use the shell_eval tool to compute: 123 * 456",
    "goal": {"description": "arithmetic"},
    "required_tools": [],
    "required_capabilities": ["cpu_inference"],
    "complexity_hint": "light",
    "permission_level": "private_lan",
    "raw_input": "Use the shell_eval tool to compute: 123 * 456"
  }'

  submit_task "$task_body"
  poll_task
  fetch_events

  if [[ "$STATE" != "completed" ]]; then
    REASON="$(printf '%s' "$EVENTS" | event_payload 'route.failed,run.failed')"
    echo "✗ TOOL FAIL — Task ${STATE:-timed out} after ${ELAPSED}s"
    echo "Reason: $REASON"
    exit 1
  fi

  SUMMARY="$(printf '%s' "$EVENTS" | event_payload 'run.completed' | event_summary)"
  TOOL_CALLS="$(printf '%s' "$EVENTS" | event_count 'run.step_completed')"

  if [[ "$TOOL_CALLS" -lt 1 ]]; then
    echo "✗ TOOL FAIL — No tool_step events found"
    echo "Answer: $SUMMARY"
    exit 1
  fi

  if [[ "$SUMMARY" != *"56088"* ]]; then
    echo "✗ TOOL FAIL — wrong answer"
    echo "Tool was called $TOOL_CALLS times"
    echo "Answer: $SUMMARY"
    exit 1
  fi

  echo "✓ TOOL PASS — Tool was called $TOOL_CALLS times, answer: 56088"
}

read_key
echo "Using API key: $API_KEY_FILE"
echo "Control plane: $BASE_URL"

case "$MODE" in
  quick) run_quick_test ;;
  tool) run_tool_test ;;
esac
