# LSP Sidecar Broker (spike)

Status: transport spike — proven end-to-end by `./spike.sh` (unit tests +
fake server + real `typescript-language-server` handshake). Not yet wired
into the app.

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
  (stdin pipe held open; closing it = app death = broker+server die)
```

## Files

| File | Purpose |
|---|---|
| `lsp_broker.zig` | The broker. Single file, `std` only, Zig 0.16. Unit tests inline (`zig test lsp_broker.zig`, 18 tests). |
| `fake_lsp.zig` | Tiny Content-Length stdio server for the e2e proof (answers `initialize`, echoes `didOpen` as diagnostics). |
| `spike.sh` | Builds both, runs the transport end-to-end, prints `RESULT: PASS/FAIL`. |

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
lsp_broker <server-cmd> [args...]     # ≤16 args
```

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
| `error` | `{"event":"error","code":"...","detail":"..."}` | Non-fatal broker-level fault. Codes: `oversized_frame` (server declared > 1 MiB; payload dropped, stream continues), `malformed_frame` (framing corruption; decoder resynced to the next `Content-Length`), `decode_overflow`, `server_stdin_failed`, `spawn_failed`, `emit_failed`. |
| `server_exit` | `{"event":"server_exit","reason":"exited"\|"signal"\|"unknown","code":N}` | The language server ended. Always the broker's last line; the broker then exits. |

### HTTP POST (app → server)

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
| POST body | 64 KiB (SDK fetch cap) |
| HTTP request head | 8 KiB |

Framing corruption never kills the session: the decoder skips oversized
payloads without buffering them and resyncs to the next plausible
`Content-Length` header after malformed input.

## Lifecycle / kill semantics

- The broker exits when **either**:
  1. its **stdin closes** (the app died or cancelled the spawn effect):
     it SIGTERMs the server's process group and exits 0; or
  2. the **server exits** (stdout EOF): it reaps the child, emits
     `server_exit`, and exits 0.
- The server is spawned with `pgid = 0` (its own process group), so the
  broker kills `-pid` — the whole server tree (e.g. `typescript-language-server`
  *and* its `tsserver` node child). Verified by `spike.sh`.

### Process Governor ownership plan

The broker is the **one governed child** per language session:

- Governor spawns it via the SDK `spawn` effect (`.lines`,
  `max_line_bytes = 256 KiB`) and records the spawn key.
- `cancel(key)` closes the broker's stdin → broker kills the server tree
  → SDK delivers exactly one `on_exit`. No zombies: the broker always
  waits on its child; the SDK worker always reaps the broker.
- Server crash surfaces as `server_exit` + broker exit + `on_exit` —
  the Governor's existing restart/backoff policy applies to the broker
  spawn only; it never needs to know the server's pid.
- Production hardening (not in spike): TERM → grace → KILL escalation,
  and optionally `PR_SET_PDEATHSIG(SIGKILL)` on Linux as a belt-and-
  braces backstop if the broker itself is SIGKILLed.

## Threat notes

- **Bind**: `127.0.0.1` only, ephemeral port. Never `0.0.0.0`, never a
  fixed port (no squatting/collision).
- **Auth**: every POST must echo the 128-bit random per-run token
  (`X-Broker-Token`, length-guarded constant-time compare). The token
  travels only through the broker's stdout pipe to the app — other local
  processes can see the port but cannot speak without the token.
- **Bounded everything**: fixed pre-allocated buffers; oversized input is
  rejected (never buffered), so a hostile/buggy server or client cannot
  balloon broker memory. No dynamic allocation after startup.
- **No shell**: the server command is exec'd from argv, never a shell
  string.
- Payloads are treated as opaque bytes; the broker never parses message
  JSON (no parser attack surface beyond header/number parsing).

## App-side integration contract (exact)

1. Governor `spawn`s `lsp_broker <server...>` with `output = .lines`,
   `max_line_bytes = 256 * 1024`, keeping the spawn key. **Do not close
   stdin conceptually** — the SDK's one-shot stdin write should be empty;
   the pipe stays open until cancel. *(Verify: SDK closes child stdin
   after the one-shot write — capability report says "written once, then
   stdin closes". If so, pass a long-lived marker: the broker must be
   given `--stay` … see Open risks #1 below.)*
2. On first `on_line`: parse `listening`, store `port` + `token`.
3. Send client→server messages with `fetch` POST as above; chunk at
   > 64 KiB. Serialize chunked sends.
4. On `on_line` events: `message` → feed payload to the existing
   `src/lsp/jsonrpc.zig` / `broker.zig` session layer; `message_chunk` →
   reassemble (mirror of `ChunkAssembler`); `error` → log/telemetry;
   `server_exit` → mark session stopped.
5. Teardown: `cancel(spawn_key)`. Exactly one `on_exit` follows.

## Open risks for productionizing

1. **Confirmed SDK conflict — stdin liveness cannot work under SDK
   governance.** The installed SDK always leaves a spawned child with a
   closed/EOF stdin: `effects.zig:3721` spawns with
   `.stdin = if (slot.stdin_len > 0) .pipe else .ignore` (`.ignore` =
   /dev/null → immediate EOF) and, for `.pipe`, writes the ≤ 4 KiB
   one-shot then `stdin_file.close(io)` (`effects.zig:3745`). A broker
   spawned by the SDK would see stdin EOF instantly and self-terminate.
   Before app integration the broker needs a `--liveness=http` mode:
   app `POST /ping` every T seconds, broker kills the tree after 3T
   silence (transport unchanged, ~20 broker lines). Stdin mode remains
   correct for spike.sh and non-SDK supervisors; `cancel(key)` teardown
   is unaffected either way (the SDK kills+reaps the broker directly).
2. Windows: raw-fd I/O and process groups are POSIX; a Windows build
   needs Job Objects + WinSock variants of the I/O layer.
3. Single-assembly chunk POSTs assume one in-flight large send; if the
   app ever parallelizes sends per session, key assemblies by id.
