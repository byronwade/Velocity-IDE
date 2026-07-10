#!/usr/bin/env bash
# End-to-end proof for the PTY sidecar broker: a REAL pseudo-terminal
# (not a pipe), driven through the SDK-shaped transport.
#
#   unit tests (broker + app transport) -> build -> start pty_broker
#   owning an interactive bash -> assert `tty` inside reports a pts
#   (real PTY, not a pipe) -> POST /input "echo VELOCITY_PTY_$((6*7))"
#   and assert the shell EXPANDED it to VELOCITY_PTY_42 (interactive
#   round trip) -> POST /resize 120x40 and assert `stty size` sees it
#   (TIOCSWINSZ + SIGWINCH) -> background sleeper + POST /shutdown and
#   assert the whole shell tree is reaped -> separate run: `exit` in
#   the shell yields pty_exit code 0 and the broker exits by itself.
#
# Prints PASS or FAIL. Linux only (see README platform gates).

set -u
cd "$(dirname "$0")"

ZIG="${ZIG:-$HOME/.native/toolchains/zig-0.16.0/zig}"
OUT="out"
NDJSON="$OUT/pty.ndjson"
FAILURES=0

note() { printf '%s\n' "$*"; }
check() { # check <label> <ok:0|1>
  if [ "$2" -eq 0 ]; then
    note "ok   - $1"
  else
    note "FAIL - $1"
    FAILURES=$((FAILURES + 1))
  fi
}

# Decode every data event's base64 payload in order -> raw terminal bytes.
decoded_output() { # decoded_output [file]
  local file="${1:-$NDJSON}"
  grep -o '"b64":"[^"]*"' "$file" 2>/dev/null | cut -d'"' -f4 |
    while IFS= read -r b; do printf '%s' "$b" | base64 -d 2>/dev/null; done
}

wait_for_output() { # wait_for_output <pattern> <timeout_s> [file]
  local deadline=$((SECONDS + $2))
  while [ $SECONDS -lt $deadline ]; do
    decoded_output "${3:-$NDJSON}" | grep -q "$1" && return 0
    sleep 0.05
  done
  return 1
}

wait_for_line() { # wait_for_line <pattern> <timeout_s> [file]
  local file="${3:-$NDJSON}"
  local deadline=$((SECONDS + $2))
  while [ $SECONDS -lt $deadline ]; do
    grep -q "$1" "$file" 2>/dev/null && return 0
    sleep 0.05
  done
  return 1
}

post_input() { # post_input <port> <token> <text...>  (sends text verbatim + \n)
  local port="$1" token="$2"; shift 2
  local b64
  b64=$(printf '%s\n' "$*" | base64 -w0)
  curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$port/input" \
    -H "X-Broker-Token: $token" --data "{\"b64\":\"$b64\"}"
}

mkdir -p "$OUT"

note "== unit tests (zig test pty_broker.zig — includes the imported lsp_broker suite) =="
"$ZIG" test pty_broker.zig || { note "FAIL - broker unit tests"; echo "RESULT: FAIL"; exit 1; }

note "== unit tests (zig test ../src/terminal/pty_transport.zig) =="
"$ZIG" test ../src/terminal/pty_transport.zig || { note "FAIL - transport unit tests"; echo "RESULT: FAIL"; exit 1; }

note "== build =="
"$ZIG" build-exe -O ReleaseSafe -femit-bin="$OUT/pty_broker" pty_broker.zig || { echo "RESULT: FAIL"; exit 1; }

note "== start pty_broker (liveness=http, SDK-shaped closed stdin, owning bash) =="
rm -f "$NDJSON"
"./$OUT/pty_broker" --liveness=http --hb-window-ms=10000 --grace-ms=1000 \
  --cols=80 --rows=24 -- bash --norc -i </dev/null >"$NDJSON" 2>"$OUT/pty.stderr" &
BROKER_PID=$!

wait_for_line '"event":"listening"' 10
check "broker prints listening event despite closed stdin" $?

PORT=$(grep -o '"port":[0-9]*' "$NDJSON" | head -1 | cut -d: -f2)
TOKEN=$(grep -o '"token":"[a-f0-9]*"' "$NDJSON" | head -1 | cut -d'"' -f4)
note "     port=$PORT token=${TOKEN:0:8}..."
[ -n "$PORT" ] && [ -n "$TOKEN" ]
check "port and token parsed from first NDJSON line" $?

# App-style heartbeat pump for the whole scenario.
(
  while curl -s -o /dev/null -X POST "http://127.0.0.1:$PORT/hb" -H "X-Broker-Token: $TOKEN" --data ''; do
    sleep 2
  done
) &
HB_PUMP_PID=$!

note "== auth: POST without token is rejected =="
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/input" \
  --data '{"b64":"dHR5Cg=="}')
[ "$CODE" = "401" ]
check "unauthenticated POST /input -> 401 (got $CODE)" $?
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/resize" \
  --data '{"cols":100,"rows":30}')
[ "$CODE" = "401" ]
check "unauthenticated POST /resize -> 401 (got $CODE)" $?

note "== real PTY: tty(1) inside the shell reports a pts device =="
CODE=$(post_input "$PORT" "$TOKEN" 'tty')
[ "$CODE" = "204" ]
check "POST /input tty -> 204 (got $CODE)" $?
wait_for_output '/dev/pts/' 5
check "shell runs on /dev/pts/N (a real PTY, not a pipe)" $?

note "== interactive round trip: shell expands \$((6*7)) =="
T0=$(date +%s%N)
CODE=$(post_input "$PORT" "$TOKEN" 'echo VELOCITY_PTY_$((6*7))')
[ "$CODE" = "204" ]
check "POST /input echo VELOCITY_PTY_\$((6*7)) -> 204 (got $CODE)" $?
wait_for_output 'VELOCITY_PTY_42' 5
RT=$?
T1=$(date +%s%N)
check "NDJSON output contains VELOCITY_PTY_42 (shell-expanded, echoed back)" $RT
note "     input POST -> decoded echo latency (incl. curl fork/exec + 50ms poll): $(( (T1 - T0) / 1000000 )) ms"

note "== resize: TIOCSWINSZ propagates to the shell =="
STTY0=$(decoded_output | grep -c '40 120')
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/resize" \
  -H "X-Broker-Token: $TOKEN" --data '{"cols":120,"rows":40}')
[ "$CODE" = "204" ]
check "POST /resize 120x40 -> 204 (got $CODE)" $?
CODE=$(post_input "$PORT" "$TOKEN" 'stty size')
wait_for_output '40 120' 5
check "stty size reports 40 120 after resize" $?
[ "$STTY0" -eq 0 ]
check "the 40 120 reading appeared only after the resize" $?

note "== resize: malformed and out-of-range bodies are refused =="
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/resize" \
  -H "X-Broker-Token: $TOKEN" --data '{"cols":0,"rows":40}')
[ "$CODE" = "400" ]
check "POST /resize cols=0 -> 400 (got $CODE)" $?
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/resize" \
  -H "X-Broker-Token: $TOKEN" --data 'not json')
[ "$CODE" = "400" ]
check "POST /resize garbage -> 400 (got $CODE)" $?

note "== POST /shutdown reaps the whole shell tree (incl. background child) =="
pkill -fx 'sleep 3707' 2>/dev/null # stale markers from an aborted earlier run
CODE=$(post_input "$PORT" "$TOKEN" 'sleep 3707 &')
sleep 0.5
SLEEPERS_BEFORE=$(pgrep -fx 'sleep 3707' | wc -l)
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/shutdown" \
  -H "X-Broker-Token: $TOKEN" --data '')
[ "$CODE" = "204" ]
check "POST /shutdown -> 204 (got $CODE)" $?
for _ in $(seq 100); do kill -0 "$BROKER_PID" 2>/dev/null || break; sleep 0.05; done
! kill -0 "$BROKER_PID" 2>/dev/null
check "broker exits after /shutdown" $?
grep -q '"event":"broker_exit","reason":"shutdown_requested"' "$NDJSON"
check "broker_exit event names the shutdown request" $?
sleep 0.3
SLEEPERS_AFTER=$(pgrep -fx 'sleep 3707' | wc -l)
[ "$SLEEPERS_BEFORE" -ge 1 ] && [ "$SLEEPERS_AFTER" -eq 0 ]
check "shell tree reaped (sleep 3707 procs: $SLEEPERS_BEFORE -> $SLEEPERS_AFTER)" $?
kill "$HB_PUMP_PID" 2>/dev/null
wait "$HB_PUMP_PID" 2>/dev/null

note "== natural shell exit yields pty_exit and the broker exits by itself =="
EXIT_NDJSON="$OUT/pty-exit.ndjson"
rm -f "$EXIT_NDJSON"
"./$OUT/pty_broker" --liveness=http --hb-window-ms=10000 --grace-ms=1000 \
  -- bash --norc -i </dev/null >"$EXIT_NDJSON" 2>/dev/null &
EXIT_PID=$!
wait_for_line '"event":"listening"' 10 "$EXIT_NDJSON"
check "second broker prints listening" $?
EPORT=$(grep -o '"port":[0-9]*' "$EXIT_NDJSON" | head -1 | cut -d: -f2)
ETOKEN=$(grep -o '"token":"[a-f0-9]*"' "$EXIT_NDJSON" | head -1 | cut -d'"' -f4)
CODE=$(post_input "$EPORT" "$ETOKEN" 'exit 0')
[ "$CODE" = "204" ]
check "POST /input exit 0 -> 204 (got $CODE)" $?
wait_for_line '"event":"pty_exit"' 10 "$EXIT_NDJSON"
check "pty_exit event emitted after the shell exits" $?
grep -q '"event":"pty_exit","reason":"exited","code":0' "$EXIT_NDJSON"
check "pty_exit reports clean exit code 0" $?
for _ in $(seq 100); do kill -0 "$EXIT_PID" 2>/dev/null || break; sleep 0.05; done
! kill -0 "$EXIT_PID" 2>/dev/null
check "broker process exits after pty_exit" $?

note ""
note "== key transcript lines ($NDJSON) =="
grep -E '"event":"(listening|broker_exit)"' "$NDJSON" | cut -c1-160
note "-- decoded terminal output (tail) --"
decoded_output | tr -d '\r' | grep -a -E 'pts|VELOCITY_PTY_42|40 120' | head -6
grep -E '"event":"pty_exit"' "$EXIT_NDJSON" | cut -c1-160

note ""
if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT: PASS"
  exit 0
else
  echo "RESULT: FAIL ($FAILURES check(s) failed)"
  exit 1
fi
