#!/usr/bin/env bash
# End-to-end transport proof for the LSP sidecar broker (no real
# language server required — uses fake_lsp.zig).
#
#   unit tests -> build -> start broker -> POST via curl (token auth,
#   chunked POST reassembly) -> assert NDJSON responses on broker
#   stdout -> assert lifecycle (stdin close kills broker + server).
#
# Prints PASS or FAIL. Optional: set REAL_LSP="typescript-language-server --stdio"
# (or zls) to also run a real initialize handshake.

set -u
cd "$(dirname "$0")"

ZIG="${ZIG:-$HOME/.native/toolchains/zig-0.16.0/zig}"
OUT="out"
NDJSON="$OUT/broker.ndjson"
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

wait_for_line() { # wait_for_line <pattern> <timeout_s>
  local deadline=$((SECONDS + $2))
  while [ $SECONDS -lt $deadline ]; do
    grep -q "$1" "$NDJSON" 2>/dev/null && return 0
    sleep 0.05
  done
  return 1
}

mkdir -p "$OUT"

note "== unit tests (zig test lsp_broker.zig) =="
"$ZIG" test lsp_broker.zig || { note "FAIL - unit tests"; echo "RESULT: FAIL"; exit 1; }

note "== build =="
"$ZIG" build-exe -O ReleaseSafe -femit-bin="$OUT/lsp_broker" lsp_broker.zig || { echo "RESULT: FAIL"; exit 1; }
"$ZIG" build-exe -O ReleaseSafe -femit-bin="$OUT/fake_lsp" fake_lsp.zig || { echo "RESULT: FAIL"; exit 1; }

note "== start broker (owning fake_lsp) =="
rm -f "$NDJSON" "$OUT/stdin.fifo"
mkfifo "$OUT/stdin.fifo"
"./$OUT/lsp_broker" "./$OUT/fake_lsp" <"$OUT/stdin.fifo" >"$NDJSON" 2>"$OUT/broker.stderr" &
BROKER_PID=$!
exec 9>"$OUT/stdin.fifo" # hold the broker's stdin open (we are "the app")

wait_for_line '"event":"listening"' 10
check "broker prints listening event" $?

PORT=$(grep -o '"port":[0-9]*' "$NDJSON" | head -1 | cut -d: -f2)
TOKEN=$(grep -o '"token":"[a-f0-9]*"' "$NDJSON" | head -1 | cut -d'"' -f4)
note "     port=$PORT token=${TOKEN:0:8}..."
[ -n "$PORT" ] && [ -n "$TOKEN" ]
check "port and token parsed from first NDJSON line" $?

note "== auth: POST without token is rejected =="
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/message" \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
[ "$CODE" = "401" ]
check "unauthenticated POST -> 401 (got $CODE)" $?

note "== initialize round trip =="
T0=$(date +%s%N)
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/message" \
  -H "X-Broker-Token: $TOKEN" -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":42,"method":"initialize","params":{"capabilities":{}}}')
[ "$CODE" = "204" ]
check "authenticated initialize POST -> 204 (got $CODE)" $?

wait_for_line '"id":42' 5
RT=$?
T1=$(date +%s%N)
check "NDJSON initialize response with matching id 42 on broker stdout" $RT
grep -q '"serverInfo":{"name":"fake-lsp"' "$NDJSON"
check "initialize result carries fake-lsp serverInfo" $?
note "     initialize POST->NDJSON latency (incl. curl fork/exec + 50ms poll): $(( (T1 - T0) / 1000000 )) ms"

note "== chunked POST reassembly (didOpen split into 3 chunks) =="
DIDOPEN='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///workspace/chunked.zig","languageId":"zig","version":1,"text":"const x = 1;"}}}'
LEN=${#DIDOPEN}
P1=${DIDOPEN:0:60}
P2=${DIDOPEN:60:60}
P3=${DIDOPEN:120}
for i in 0 1 2; do
  case $i in
    0) DATA="$P1" LAST=0 ;;
    1) DATA="$P2" LAST=0 ;;
    2) DATA="$P3" LAST=1 ;;
  esac
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/chunk" \
    -H "X-Broker-Token: $TOKEN" -H "X-Chunk-Id: 7" -H "X-Chunk-Seq: $i" -H "X-Chunk-Last: $LAST" \
    --data-binary "$DATA")
  [ "$CODE" = "204" ] || break
done
[ "$CODE" = "204" ]
check "all 3 chunk POSTs -> 204" $?

wait_for_line 'file:///workspace/chunked.zig' 5
check "publishDiagnostics echoes the uri from the reassembled didOpen" $?
grep -q "fake-lsp saw didOpen ($LEN payload bytes)" "$NDJSON"
check "server received exactly the reassembled $LEN-byte message" $?

note "== out-of-order chunk is rejected =="
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/chunk" \
  -H "X-Broker-Token: $TOKEN" -H "X-Chunk-Id: 8" -H "X-Chunk-Seq: 5" -H "X-Chunk-Last: 1" \
  --data-binary 'orphan')
[ "$CODE" = "409" ]
check "chunk with seq 5 and no seq 0 -> 409 (got $CODE)" $?

note "== lifecycle: server exit is forwarded, broker exits =="
curl -s -o /dev/null -X POST "http://127.0.0.1:$PORT/message" \
  -H "X-Broker-Token: $TOKEN" --data '{"jsonrpc":"2.0","id":43,"method":"shutdown"}'
curl -s -o /dev/null -X POST "http://127.0.0.1:$PORT/message" \
  -H "X-Broker-Token: $TOKEN" --data '{"jsonrpc":"2.0","method":"exit"}'
wait_for_line '"event":"server_exit"' 5
check "server_exit event on broker stdout" $?
grep -q '"event":"server_exit","reason":"exited","code":0' "$NDJSON"
check "server_exit reports clean exit code 0" $?

for _ in $(seq 40); do kill -0 "$BROKER_PID" 2>/dev/null || break; sleep 0.05; done
! kill -0 "$BROKER_PID" 2>/dev/null
check "broker process exited after server exit" $?
exec 9>&- # release our end of the fifo
rm -f "$OUT/stdin.fifo"

note "== lifecycle: stdin close (app death) kills broker + server tree =="
mkfifo "$OUT/stdin.fifo"
"./$OUT/lsp_broker" "./$OUT/fake_lsp" <"$OUT/stdin.fifo" >"$OUT/broker2.ndjson" 2>/dev/null &
BROKER2_PID=$!
exec 9>"$OUT/stdin.fifo"
deadline=$((SECONDS + 10))
until grep -q '"event":"listening"' "$OUT/broker2.ndjson" 2>/dev/null; do
  [ $SECONDS -lt $deadline ] || break
  sleep 0.05
done
FAKE_PIDS_BEFORE=$(pgrep -f "$OUT/fake_lsp" | wc -l)
exec 9>&- # simulate app death: broker stdin closes
for _ in $(seq 40); do kill -0 "$BROKER2_PID" 2>/dev/null || break; sleep 0.05; done
! kill -0 "$BROKER2_PID" 2>/dev/null
check "broker exits when its stdin closes" $?
sleep 0.3
FAKE_PIDS_AFTER=$(pgrep -f "$OUT/fake_lsp" | wc -l)
[ "$FAKE_PIDS_BEFORE" -ge 1 ] && [ "$FAKE_PIDS_AFTER" -eq 0 ]
check "language-server tree torn down (fake_lsp procs: $FAKE_PIDS_BEFORE -> $FAKE_PIDS_AFTER)" $?
rm -f "$OUT/stdin.fifo"

if [ -n "${REAL_LSP:-}" ]; then
  note "== bonus: real language server handshake ($REAL_LSP) =="
  mkfifo "$OUT/stdin.fifo"
  # shellcheck disable=SC2086
  "./$OUT/lsp_broker" $REAL_LSP <"$OUT/stdin.fifo" >"$OUT/real.ndjson" 2>/dev/null &
  REAL_PID=$!
  exec 9>"$OUT/stdin.fifo"
  deadline=$((SECONDS + 15))
  until grep -q '"event":"listening"' "$OUT/real.ndjson" 2>/dev/null; do
    [ $SECONDS -lt $deadline ] || break
    sleep 0.05
  done
  RPORT=$(grep -o '"port":[0-9]*' "$OUT/real.ndjson" | head -1 | cut -d: -f2)
  RTOKEN=$(grep -o '"token":"[a-f0-9]*"' "$OUT/real.ndjson" | head -1 | cut -d'"' -f4)
  INIT_OPTS="${REAL_LSP_INIT_OPTS:-}"
  [ -n "$INIT_OPTS" ] || INIT_OPTS='{}'
  curl -s -o /dev/null -X POST "http://127.0.0.1:$RPORT/message" \
    -H "X-Broker-Token: $RTOKEN" \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":\"file://$PWD\",\"capabilities\":{},\"initializationOptions\":$INIT_OPTS}}"
  deadline=$((SECONDS + 20))
  until grep -q '"id":1' "$OUT/real.ndjson" 2>/dev/null; do
    [ $SECONDS -lt $deadline ] || break
    sleep 0.1
  done
  grep -q '"id":1' "$OUT/real.ndjson"
  check "real LSP initialize response arrived as NDJSON" $?
  if grep -q '"id":1,.*"result":{.*"capabilities"' "$OUT/real.ndjson"; then
    note "ok   - real LSP initialize returned a result with capabilities"
  else
    note "note - real LSP replied over the transport, but not with a success result:"
    grep '"id":1' "$OUT/real.ndjson" | cut -c1-160
  fi
  exec 9>&-
  for _ in $(seq 40); do kill -0 "$REAL_PID" 2>/dev/null || break; sleep 0.05; done
  rm -f "$OUT/stdin.fifo"
else
  note "note - no real language server configured (set REAL_LSP=... to test one)"
fi

note ""
note "== key transcript lines ($NDJSON) =="
grep -E '"event":"(listening|message|server_exit)"' "$NDJSON" | cut -c1-160

note ""
if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT: PASS"
  exit 0
else
  echo "RESULT: FAIL ($FAILURES check(s) failed)"
  exit 1
fi
