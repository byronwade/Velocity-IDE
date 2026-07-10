# Sidecar Brokers (LSP + PTY)

Two sibling binaries share one architecture (and most plumbing): the
app spawns exactly one governed broker child per language server / per
terminal; the broker owns the real child and re-frames its traffic
into the SDK's two legal channels (stdout NDJSON lines in, localhost
token-authed POSTs out).

**LSP broker** status: production-shaped transport, proven end-to-end
by `./spike.sh` (unit tests + fake server + kill-escalation scenarios
+ real `typescript-language-server` handshake through the
heartbeat-mode broker). The pure client-side state machine the app
drives lives at `../src/lsp/broker_transport.zig`; only the effect
wiring in `app_model.zig` remains (checklist below).

**PTY broker** status: proven end-to-end on Linux by `./pty-spike.sh`
(real `/dev/pts/N` interactive bash: input echo round trip, resize via
TIOCSWINSZ, session-tree reaping, natural-exit reporting). Pure app
side: `../src/terminal/pty_transport.zig`. See "PTY broker" below for
protocol and platform gates.

## Why this exists

Per `docs/velocity/sdk-capability-report.md`, the Native SDK (0.4.x) can:

- stream a long-lived child's **stdout as NDJSON lines** (event-driven,
  bounded 256 KiB/line), and
- send data to localhost via **fetch POST** (64 KiB payload cap),

but it **cannot** stream stdin to a running child and **cannot** parse
LSP's `Content-Length` stdio framing. So the app never talks to a
language server directly. It spawns exactly one governed child per
language session — this broker — and the broker owns the server.

```
  Velocity app (SDK)                    lsp_broker                LSP server
  ─────────────────                     ──────────                ──────────
  spawn .lines  ◄── stdout NDJSON ────  re-framer  ◄── stdout ──  Content-Length
  fetch POST    ──► 127.0.0.1:<port> ─► reassembly ─── stdin ──►  Content-Length
  fetch POST /hb every T ─────────────► liveness   (SDK closes child stdin;
  fetch POST /shutdown ───────────────► teardown    heartbeats replace it)
```

## Files

| File | Purpose |
|---|---|
| `lsp_broker.zig` | The LSP broker. Single file, `std` only, Zig 0.16. Unit tests inline (`zig test lsp_broker.zig`, 22 tests). Also exports the shared broker plumbing (HTTP head parsing, token compare, raw-fd I/O, clock, kill escalation, death backstop) that `pty_broker.zig` imports. |
| `pty_broker.zig` | The PTY broker (separate binary; imports the shared plumbing above). Unit tests inline (`zig test pty_broker.zig`, 16 tests + the imported 22). |
| `../src/lsp/broker_transport.zig` | Pure client state machine for the app: NDJSON event parsing, chunk (re)assembly, POST planning, LSP session/lifecycle bookkeeping, typed v1 extract/build. `zig test broker_transport.zig`, 49 tests (+3 via `jsonrpc.zig`). No SDK calls, no I/O. |
| `../src/terminal/pty_transport.zig` | Pure client state machine for the terminal: PTY NDJSON event parsing, bounded base64 decode into a caller buffer, `/input`/`/resize` body builders (`InputPlan` chunking for large pastes), starting/running/exited lifecycle. `zig test pty_transport.zig`, 25 tests. No SDK calls, no I/O. |
| `fake_lsp.zig` | Tiny Content-Length stdio server for the e2e proof (answers `initialize`, echoes `didOpen` as diagnostics). |
| `spike.sh` | LSP e2e: builds, runs the transport + lifecycle scenarios, prints `RESULT: PASS/FAIL`. |
| `pty-spike.sh` | PTY e2e: real interactive bash on a real PTY through the broker, prints `RESULT: PASS/FAIL`. |

Build (toolchain already present in the repo image):

```sh
ZIG=~/.native/toolchains/zig-0.16.0/zig ./spike.sh          # fake-server proof
REAL_LSP="typescript-language-server --stdio" ./spike.sh    # + real handshake
# ts-ls needs a workspace TypeScript; point it at one explicitly:
#   REAL_LSP_INIT_OPTS='{"tsserver":{"path":"/path/to/node_modules/typescript/lib/tsserver.js"}}'
```

## Protocol

### Startup

```
lsp_broker [--liveness=stdin|http] [--hb-window-ms=N] [--grace-ms=N] [--] <server-cmd> [args...]
```

- `--liveness=stdin` (default): exit when the broker's stdin hits EOF.
  Correct for CLI/supervisor use where the parent holds the pipe open.
- `--liveness=http`: **required under the SDK** (it always closes a
  spawned child's stdin — `effects.zig` writes the one-shot then
  closes). Stdin EOF is ignored; instead the app must `POST /hb` at
  least every `--hb-window-ms` (default 30000, must be > 0). A lapse
  tears down the server tree and exits.
- `--grace-ms` (default 3000): SIGTERM → SIGKILL escalation grace used
  on every exit path.
- `--` separates broker flags from a server command that itself starts
  with `--`. Server argv ≤ 16 args.

The broker binds `127.0.0.1:0` (ephemeral, localhost only), generates a
random 128-bit token, spawns the server (own process group, stdio piped,
stderr discarded), and prints exactly one line first on stdout:

```json
{"event":"listening","port":38617,"token":"fee8c75f408e830831425370bb633345"}
```

### Broker stdout: NDJSON events (server → app)

One JSON object per line, never longer than 256 KiB. Events:

| Event | Shape | Meaning |
|---|---|---|
| `listening` | `{"event":"listening","port":N,"token":"hex32"}` | First line. Where to POST + auth token. |
| `message` | `{"event":"message","payload":{...}}` | One complete LSP message from the server, embedded **raw** (not string-escaped). Raw `\n`/`\r` inter-token whitespace is replaced by spaces so the payload is one line; string contents are untouched (valid JSON already escapes control chars). Emitted when the sanitized payload is ≤ 192 KiB. |
| `message_chunk` | `{"event":"message_chunk","id":N,"seq":I,"last":bool,"data_b64":"..."}` | Server message too big for one line. Chunks of ≤ 96 KiB raw, base64-encoded. Concatenate decoded chunks for one `id` in `seq` order; `last:true` completes the message. Chunk ids increase monotonically per broker run. |
| `error` | `{"event":"error","code":"...","detail":"..."}` | Non-fatal broker-level fault (except `heartbeat_lapsed`, which precedes a `broker_exit`). Codes: `oversized_frame` (server declared > 1 MiB; payload dropped, stream continues), `malformed_frame` (framing corruption; decoder resynced to the next `Content-Length`), `decode_overflow`, `server_stdin_failed`, `spawn_failed`, `emit_failed`, `heartbeat_lapsed`. |
| `server_exit` | `{"event":"server_exit","reason":"exited"\|"signal"\|"unknown","code":N}` | The language server ended **on its own**. Last line; the broker reaps stragglers and exits. |
| `broker_exit` | `{"event":"broker_exit","reason":"stdin_closed"\|"heartbeat_lapsed"\|"shutdown_requested"}` | The **broker** initiated teardown. Last line; the server tree is escalate-killed and the broker exits 0. A broker-initiated teardown emits `broker_exit`, not `server_exit`. |

Exactly one of `server_exit` / `broker_exit` is the final line of every
run (after `listening` was printed).

### HTTP POST (app → broker)

All requests: `POST`, header `X-Broker-Token: <token>` (exact echo of the
startup token). Responses carry `Connection: close`; use one connection
per request (matches SDK `fetch`).

- `POST /message` — body is one complete LSP JSON-RPC message (raw JSON,
  no Content-Length header framing), body ≤ 64 KiB. The broker adds the
  `Content-Length` framing and writes it to the server's stdin.
- `POST /chunk` — for messages > 64 KiB (e.g. `didOpen` of a large file).
  Extra headers: `X-Chunk-Id` (u64, same for all parts), `X-Chunk-Seq`
  (u32, 0-based, strictly sequential), `X-Chunk-Last: 1` on the final
  part. Bodies are concatenated in order; on the last part the assembled
  message (≤ 1 MiB) is framed and forwarded. `seq:0` always starts a new
  assembly (retry = start over). One assembly at a time per broker —
  the app must not interleave two chunked sends (SDK side should
  serialize; it has one fetch slot per send anyway).
  (`broker_transport.zig` plans client chunks at 48 KiB for header
  headroom under the SDK's 64 KiB fetch cap.)
- `POST /hb` — heartbeat; empty body. Re-arms the `--liveness=http`
  window. Accepted (and harmless) in stdin mode too. `204`.
- `POST /shutdown` — orderly teardown: replies `204`, emits
  `broker_exit`, escalate-kills the server tree, exits 0. Works in both
  liveness modes. Use for app-side teardown when `cancel(key)` is not
  desired (e.g. graceful shutdown while the app keeps running).

Status codes: `204` accepted · `400` malformed · `401` bad/missing token ·
`404` unknown path · `405` not POST · `409` chunk out of order / id
mismatch (assembly reset — restart at seq 0) · `413` body > 64 KiB or
assembled > 1 MiB · `431` header block > 8 KiB · `502` server stdin
closed (server is dying; expect `server_exit`).

### Bounds (hard, enforced both directions)

| Bound | Value |
|---|---|
| LSP message payload (either direction) | 1 MiB (`max_payload_bytes`) — beyond: NDJSON `error` event / HTTP 413 |
| Content-Length header block | 4 KiB |
| Inline NDJSON payload | 192 KiB (larger → `message_chunk`) |
| POST body | 64 KiB (SDK fetch cap; client chunks at 48 KiB) |
| HTTP request head | 8 KiB |

Framing corruption never kills the session: the decoder skips oversized
payloads without buffering them and resyncs to the next plausible
`Content-Length` header after malformed input.

## Lifecycle / kill semantics

The broker exits on the first of:

1. **stdin EOF** (`--liveness=stdin` only) — the app/supervisor died;
2. **heartbeat lapse** (`--liveness=http` only) — no `/hb` within the
   window (the window opens when the broker starts listening, so the
   app gets one full window to send its first heartbeat);
3. **POST /shutdown** — orderly app-requested teardown;
4. **server exit** (stdout EOF) — the child is reaped and `server_exit`
   emitted.

**Every** path runs the same escalation on the server's **process
group** (the server is spawned with `pgid = 0`, so `-pid` reaches the
whole tree, e.g. `typescript-language-server` *and* its `tsserver` node
child):

```
SIGTERM(-pgid)  →  poll up to --grace-ms (25 ms steps, reaping)  →  SIGKILL(-pgid)
```

Verified by `spike.sh` against a `trap "" TERM` server: teardown
completes in ~grace ms with the tree gone. Clean trees short-circuit
(TERM to a dead group returns immediately). Exit code is 0 on all
orderly paths; 1 only when the child could not be waited.

Backstop for broker crash/SIGKILL of the app: on Linux the broker arms
`PR_SET_PDEATHSIG(SIGTERM)` plus a SIGTERM handler that SIGKILLs the
server group and exits (async-signal-safe, no grace — this is the
crash path; orderly teardown uses `/shutdown` or `cancel`).

## Threat notes

- **Bind**: `127.0.0.1` only, ephemeral port. Never `0.0.0.0`, never a
  fixed port (no squatting/collision).
- **Auth**: every POST must echo the 128-bit random per-run token
  (`X-Broker-Token`, length-guarded constant-time compare). The token
  travels only through the broker's stdout pipe to the app — other local
  processes can see the port but cannot speak without the token. This
  includes `/hb` and `/shutdown` (no unauthenticated kill/keep-alive).
- **Bounded everything**: fixed pre-allocated buffers; oversized input is
  rejected (never buffered), so a hostile/buggy server or client cannot
  balloon broker memory. No dynamic allocation after startup.
- **No shell**: the server command is exec'd from argv, never a shell
  string.
- Payloads are treated as opaque bytes; the broker never parses message
  JSON (no parser attack surface beyond header/number parsing).

## app_model integration checklist (exact)

The pure half already exists: `src/lsp/broker_transport.zig`
(`Transport`, `Session`, builders/extractors — all `zig test`-covered).
The app model wires it to effects per the capability report's sidecar
pattern (§2.2: sidecar stdout lines are the thread→loop injection
channel; timers drive heartbeats/timeouts):

1. **Spawn** (Governor-owned): feature id **`feature.lsp-broker`**
   (already in `core/feature_registry.zig`, `max_processes` via
   `feature.lsp-process-manager`). Governor records the effect key
   (`spawnEffect`-style, like the terminal path), then Effects `spawn`:
   - `argv = { "<sidecar bin>/lsp_broker", "--liveness=http",
     "--hb-window-ms=30000", "--", "typescript-language-server",
     "--stdio" }` (≤ 16 args, ≤ 2048 bytes total; no shell);
   - `output = .lines`, `max_line_bytes = 256 * 1024`;
   - `stdin = null` (the SDK closes it either way — that is why
     liveness is http);
   - `on_line` → Msg carrying the line; `on_exit` → Msg marking the
     session dead (exactly one arrives, even after `cancel`).
2. **Handshake**: create `Transport.init(reassembly_buf)` (1 MiB
   buffer) per session. Feed every `on_line` into `transport.onLine`;
   on `.listening`, build the URL prefix
   `http://127.0.0.1:{transport.port}` and start the session.
3. **Heartbeat timer**: one **repeating** Effects timer per live broker
   (e.g. 10 s — window/3; timers cap at 16, same-key restart replaces).
   `on_fire` → fetch `POST /hb`, empty body, header
   `X-Broker-Token: transport.authToken()`. Also reuse the tick to call
   `session.expireOverdue(now_ms, ...)` for request timeouts. Cancel
   the timer when the session ends.
4. **Sends**: `transport.planSend(payload)` → iterate `OutboundPost`s →
   one `fetch` POST each (`/message` or `/chunk` + `X-Chunk-*` headers,
   bodies ≤ 48 KiB, well under the 64 KiB fetch cap). Send chunk parts
   serially (await each `on_response` before the next; one assembly at
   a time per broker). Non-204 → log + `session.fail()`.
5. **Receive**: `.lsp_message` → `classifyServerMessage`; route
   `.response` ids through `session.onInitializeResponse` /
   `onShutdownResponse` / `completeRequest`; `.publish_diagnostics` →
   `extractPublishDiagnostics` into the diagnostics model (bounded
   page); `.server_request` → reply MethodNotFound or ignore (v1);
   `.broker_error` → output channel; `.server_exit` / `.broker_exit` →
   mark stopped, cancel the heartbeat timer, let the Governor
   restart/backoff policy decide (it only ever sees the broker spawn).
6. **Lifecycle**: after `.listening` → `session.beginInitialize` +
   `buildInitialize` (root URI via `buildFileUri`) → on ok response
   send `buildInitialized` → document traffic
   (`buildDidOpen/Change/Save/Close`, URIs from `buildFileUri`).
   Teardown: `beginShutdown`/`buildShutdown` → `buildExit` → expect
   `server_exit`; or fire-and-forget `POST /shutdown`; or
   `cancel(spawn_key)` (broker dies → PDEATHSIG/heartbeat reap the
   server). All three end in exactly one `on_exit`.
7. **Permissions**: verify `app.zon` allows localhost fetch before
   shipping (capability report flags this as the one unchecked
   manifest interaction).

## Open risks for productionizing

1. ~~SDK closes child stdin → stdin liveness dies instantly~~ —
   **resolved** by `--liveness=http` (+ `/hb`), proven in `spike.sh`
   (broker survives stdin EOF, dies on lapse, tree reaped).
2. Windows: raw-fd I/O, process groups, and PDEATHSIG are POSIX/Linux;
   a Windows build needs Job Objects + WinSock variants of the I/O
   layer.
3. Single-assembly chunk POSTs assume one in-flight large send; if the
   app ever parallelizes sends per session, key assemblies by id.
   (`Transport.planSend` already allocates distinct ids.)
4. Heartbeat POSTs share the 16-slot effects budget with everything
   else; a saturated fetch queue could starve `/hb`. The 30 s default
   window vs 10 s beat leaves 3 misses of headroom; keep bulk sends
   chunk-serialized (they already must be) and the risk is theoretical.
