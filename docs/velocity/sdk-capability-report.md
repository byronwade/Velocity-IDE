# Native SDK Capability Report — @native-sdk/cli 0.4.0 vs latest (0.4.2)

Date: 2026-07-10. Investigator: Agent B (docs/scratch only; no product code changed, no SDK upgraded).

Scope: the three blockers in `docs/velocity/native-sdk-blockers.md` — (1) rich editor
surface, (2) long-running streamed child processes for LSP, (3) cross-platform PTY —
evaluated against the *installed* SDK source (the 0.4.0 package ships its full Zig
runtime under `.tools/node_modules/@native-sdk/cli/src/`) and against 0.4.2 unpacked to
`/tmp/claude-0/-home-user-Velocity-IDE/a858a959-b8df-5899-b5f0-7370bd2e5f48/scratchpad/sdk-probe/cli-0.4.2/`.

---

## 1. Version landscape

`npm view @native-sdk/cli versions/time/dist-tags` (registry.npmjs.org, 2026-07-10):

| Version | Published | Notes |
|---|---|---|
| 0.0.0 | 2026-07-08 | placeholder |
| **0.4.0** | 2026-07-08 | **pinned by this repo** |
| 0.4.1 | 2026-07-09 | |
| 0.4.2 | 2026-07-10 | `latest` |

**0.4.0 → 0.4.2 delta (full source diff, ~1.7k changed lines):**

- `src/runtime/effects.zig` — **byte-identical**. `src/runtime/api.zig` — identical.
  No change to process/fetch/timer/clipboard/file effects, no PTY, no stdin streaming,
  no file watching, no new Event variants.
- Changes are rendering polish and rebranding only: per-window `pixel_snap_scale`
  (`ui_app.zig`), hairline stroke snapping (`snapHairlineStrokeRect`), chart path
  builder (`allocPathElements`), canvas `binary_packet_version` bump to 4,
  macOS `appkit_host.m` / Windows `webview2_host.cpp` webview host fixes,
  domain rename zero-native.dev → native-sdk.dev, repo rename to `vercel-labs/native`,
  new `default_prepared_download_url`.
- No new files, no removed files.

**Conclusion: upgrading to 0.4.2 changes NO blocker verdict.** It is a low-risk patch
upgrade (same API; internal canvas packet version is runtime+host shipped together),
worth taking eventually for the WebView host fixes if the editor WebView spike proceeds
on macOS/Windows, but not required for anything below.

---

## 2. Installed-SDK API surface (evidence)

All paths relative to `/home/user/Velocity-IDE/.tools/node_modules/@native-sdk/cli/src/`.

### 2.1 Effect system (`runtime/effects.zig`, 4197 lines)

`Effects(Msg)` is TEA's Cmd half. Header comment (lines 1–63) states the delivery
contract: *"workers post fixed-size completion records into a bounded MPSC queue, nudge
the platform loop through `PlatformServices.wake_fn`, and the loop thread drains the
queue and dispatches Msgs through the app's `update`."*

**Process spawning** — `pub fn spawn(self: *Self, options: SpawnOptions) void` (line 1704):

```zig
pub const SpawnOptions = struct {           // effects.zig:819
    key: u64,
    argv: []const []const u8,               // ≤16 args, ≤2048 bytes total
    /// Written to the child's stdin once, then stdin closes.
    stdin: ?[]const u8 = null,              // ≤4096 bytes, ONE-SHOT
    output: EffectOutputMode = .lines,      // .lines streams stdout per line
    max_line_bytes: usize = 4096,           // raisable to 256 KiB ceiling
    on_line: ?LineMsgFn = null,
    on_exit: ?ExitMsgFn = null,
};
```

- Long-running children are fine: thread-per-effect (`std.Thread.spawn` line 1778,
  detached), `cancel(key)` kills+reaps, exactly-one `on_exit` guaranteed
  (`EffectExitReason`: exited/signaled/cancelled/rejected/spawn_failed, line 240).
- `.lines` mode streams stdout **newline-framed** (`EffectLine`, line 257; drops are
  counted, never silent). stderr is ignored in `.lines` mode (line 292).
- **stdin is write-once-then-close** (line 824). There is NO API to write to a running
  child's stdin. Unchanged in 0.4.2.
- Caps: `max_effects = 16` in-flight spawns+fetches (line 71), completion queue
  64 entries (line 118).

**HTTP fetch with streaming** — `pub fn fetch(...)` (line 1792), `FetchOptions` (line 857):

- `.response = .stream` frames the body into `on_line` Msgs as lines arrive — the doc
  comment names *"NDJSON and SSE endpoints that hold the connection open for a
  command's whole lifetime"* as the driver (lines 227–237). `timeout_ms` covers the
  whole stream lifetime and is raisable.
- Request caps: URL 2 KiB, 8 headers/1 KiB, **payload 64 KiB**
  (`max_effect_fetch_payload_bytes`, line 131); buffered response body 256 KiB;
  stream lines up to 256 KiB each. http/https only (line 1798) — localhost works.

**Timers** — `startTimer` (line 2203), `StartTimerOptions` (line 977): `interval_ms`
(zero rejected, so ≥1 ms), `.one_shot`/`.repeating`, up to 16 timers
(`max_effect_timers`, line 444), same-key restart replaces in place.

**Other effects**: `writeFile`/`readFile` (whole-file, 1 MiB cap, line 151);
`writeClipboard`/`readClipboard` (loop-thread pasteboard, line 1998/2012); audio;
`closeWindow`/`minimizeWindow`.

### 2.2 Event injection into the TEA loop (the keystone)

- `runtime/api.zig:258` — the full app-facing `Event` union. The cross-thread channel
  is `.effects_wake` (line 267): *"The platform loop was nudged from another thread
  (`PlatformServices.wake_fn`): apps drain their effect completion queues here."*
- `platform/types.zig:2062` — `wake_fn: ?*const fn (context) anyerror!void` and
  `pub fn wake(self: PlatformServices)` (line 2534). Implementations: macOS
  performSelectorOnMainThread-style, Win32 `PostMessage`, GTK idle, atomic counter on
  the null platform (comments at lines 2060–2072).
- `runtime/ui_app.zig:2588` — `.effects_wake => try self.drainEffects(runtime)`;
  `drainEffects` (line 1095) loops `self.effects.takeMsg()` and dispatches through
  `update`.
- **There is no public API for an app-owned thread to enqueue an arbitrary Msg.** The
  Effects MPSC push is private; the `pub fn feedLine/feedExit/feedResponse/...`
  functions (lines 2939–3283) are fake-executor/replay hooks (`error.EffectNotFound`
  against the real executor's slots). `UiApp.dispatch` (ui_app.zig:1057) is loop-thread
  only.
- **Supported thread→loop channels therefore are exactly:** spawn `on_line`/`on_exit`,
  fetch `on_line`/`on_response`, timer `on_fire`, file/clipboard results, audio events.
  Two legal patterns follow:
  1. **Sidecar process**: put the background work in a child process; its stdout lines
     ARE the injection mechanism, with real wakeups (no polling latency).
  2. **Timer-drained queue**: app-owned thread + mutex/ring buffer + a `.repeating`
     Effects timer (e.g. 8–16 ms) whose `on_fire` Msg drains the queue in `update`.
     Bounded latency = interval; fully supported API; no SDK internals touched.

### 2.3 WebView embedding + bidirectional messaging

- Shell views: `ViewKind.webview` (`primitives/app_manifest/types.zig:321`), with
  `parent`/`edge`/layout fields (`ShellView`, line 383).
- **`UiApp` webview panes**: `Options.web_panes` (ui_app.zig:586, `max_web_panes = 4`,
  line 50) — model-declared `WebViewPane { label, anchor, frame, url, reload_token }`
  (line 196) that snaps a scene-declared webview to a **canvas widget's layout frame**
  and drives navigation from the model (subject to
  `security.navigation.allowed_origins`).
- **JS → native**: bridge dispatcher (`bridge/root.zig`) — sync `HandlerFn` and async
  `AsyncHandlerFn`/`AsyncResponder` (lines 79–113), 1 MiB message/response caps,
  per-command origin policy. Async responses route through `runtime.respondToBridge`
  (`runtime/async_bridge.zig`).
- **Native → JS**: `runtime.emitWindowEvent(window_id, name, detail_json)`
  (`runtime/flow.zig:172` → `platform/types.zig:2446`); JS side subscribes with
  `window.zero.on(name, cb)` (`native-sdk.d.ts:537`, `NativeSdkApi.on<T>(name, ...)`).
  The d.ts also exposes `invoke`, `webviews.create/setFrame/navigate/...`,
  `dialogs`, `clipboard`.
- Linux host already links WebKitGTK 6.0 (per blockers log) — the runtime dependency
  is already paid.

### 2.4 Textarea capabilities (`primitives/canvas/`)

- `Widget.text_selection: ?TextSelection` (widgets.zig:788) — **model-owned selection**
  (`TextSelection { anchor, focus }`, text_interaction.zig:41).
- `TextInputEvent` (text_interaction.zig:77): `insert_text`, deletes, `move_caret`
  (char/word/start/end, extend), **`set_selection`**, IME `set_composition` /
  `commit_composition` / `cancel_composition`. Keyboard events reach the app as
  `canvas_widget_keyboard` with the applied edit.
- **Scroll offset is `widget.value` and is model-owned**:
  `widgetTextInputScrollOffset` clamps `widget.value`
  (widget_text_input.zig:92–95); the runtime clamps retained offsets via
  `clampCanvasWidgetLayoutTextOffsets` (canvas_widget_runtime.zig:904) and retains
  user scroll in `value` across rebuilds (line 703). `.textarea` is a scrollable kind
  (`canvasWidgetScrollableKind`, canvas_widget_runtime.zig:421), so user wheel scrolls
  emit `canvas_widget_scroll` events with post-change `ScrollState` (api.zig:90).
- **Caret/selection pixel geometry is exported as pure functions**
  (`primitives/canvas/root.zig:615–728`): `textGeometryForWidget` →
  `WidgetTextGeometry { caret_bounds, selection_bounds, composition_bounds }`
  (widget_text_input.zig:249), `textInputViewportForWidget`,
  `textSelectionForWidgetPoint`, `textOffsetForWidgetPoint`,
  `clampedTextInputScrollOffsetForWidget`, plus deterministic line height / line count.
- **What does not exist**: a gutter slot, per-line/per-range decorations, styled spans
  inside a textarea — `widgetTextInputDrawText` draws `widget.text` as one
  single-color run (widget_text_input.zig:174). No change in 0.4.2. Whole-view text is
  bounded by `max_canvas_widget_text_bytes_per_view`.

### 2.5 Other capabilities

| Capability | 0.4.0 | Evidence |
|---|---|---|
| Native dialogs | **Yes** (loop-thread sync) | `runtime/system_services.zig:69–84` `showOpenDialog/showSaveDialog/showMessageDialog`; options in `platform/types.zig:1151+` |
| Clipboard (text + MIME data) | Yes | effects + `system_services.zig:32–48` |
| File watching | **No** | no inotify/FSEvents/kqueue anywhere in `src/` (verified grep); app already substitutes a keyed repeating-timer disk poll |
| Notifications, credentials, tray | Yes | `system_services.zig:84–135` |
| Custom drawing/input surface | Partial | `gpu_surface` shell views with raw `gpu_surface_input` events (api.zig:275) + retained widget tree; no app-level raw draw-command escape hatch in the widget tree (`chart` is the only data-drawing leaf, widgets.zig:101) |
| PTY | **No** | only grep hit is iOS simctl `--console-pty` tooling (`tooling/ios.zig:337`) |
| Streamed stdin to child | **No** | `SpawnOptions.stdin` one-shot ≤4 KiB (effects.zig:824) |

Permissions note: `security/root.zig:3–11` defines `permission_network`,
`permission_filesystem`, etc. The app manifest (`apps/native-shell/app.zon:8`)
declares only `view, command`. `effects.zig` shows no permission gate on
spawn/fetch, but any spike using `fetch` should verify manifest validation does not
require adding `network`.

---

## 3. Capability matrix

| Capability | 0.4.0 | 0.4.2 (latest) | Workaround feasibility |
|---|---|---|---|
| One-shot process (collect stdout+stderr tail) | Yes | Yes (identical) | n/a — in use today (`app_model.zig:4202`) |
| Long-running process, streamed stdout | Yes (`.lines`, newline-framed, ≤256 KiB/line) | Yes (identical) | n/a |
| Write to running child's stdin | **No** | **No** | **Yes** — sidecar broker: input via localhost HTTP POST (`fetch`), output via spawn `.lines` |
| Content-Length-framed stdio (LSP) | No (newline framing only) | No | **Yes** — broker re-frames LSP↔NDJSON |
| PTY (spawn/resize/stream) | **No** | **No** | **Yes** — broker owns the PTY (posix openpty; ConPTY later), same transport |
| Non-UI-thread → TEA loop injection | Internal only (`wake_fn` → `.effects_wake` → `takeMsg`) | identical | **Yes (bounded)** — sidecar lines (event-driven) or repeating timer draining an app-owned queue (poll, ≥1 ms) |
| Streaming HTTP (NDJSON/SSE, long-lived) | Yes (`fetch .stream`) | Yes | n/a — this is the broker's second leg |
| Timers (one-shot/repeating) | Yes (16, ≥1 ms) | Yes | n/a |
| WebView embed anchored to canvas layout | Yes (`web_panes`, max 4) | Yes (+ macOS/Win host fixes) | n/a |
| WebView bidirectional messaging | Yes (bridge invoke 1 MiB / `emitWindowEvent` + `zero.on`) | Yes | n/a |
| Textarea: model-owned selection/caret | Yes (`text_selection`, `set_selection`) | Yes | n/a |
| Textarea: model-owned scroll + scroll events | Yes (`value` + `canvas_widget_scroll`) | Yes | n/a |
| Textarea: caret/selection pixel geometry | Yes (`textGeometryForWidget`, pure) | Yes | n/a |
| Textarea: gutter slot / decorations / spans | **No** (single-color plain run) | **No** | **Partial** — sibling gutter column synced via shared `value` + line-height math; in-text highlighting NOT achievable in textarea |
| File watching | No | No | Timer polling (already shipped) |
| Native dialogs / clipboard / notifications | Yes | Yes | n/a |

---

## 4. Blocker verdicts

### Blocker 1 — Rich editor surface: **SPIKE** (two-track)

**(a) 0.4.0 support:** better than the blockers log records. The textarea contract for
gutter/caret/scroll sync *does* exist, just undocumented: scroll offset is the widget's
`value` (model-owned, clamped, user scrolls echoed via `canvas_widget_scroll`),
selection is `text_selection` (model-owned), and `canvas.textGeometryForWidget` /
`textInputViewportForWidget` give exact caret/selection/viewport pixel rects from pure
functions the app can call in `view`. What is genuinely missing is in-text styling
(spans/decorations) — the textarea paints one single-color text run.

**(b) 0.4.2:** no change.

**(c) Recommendation — SPIKE, in this order:**

1. **Gutter spike (1–2 days, pure 0.4.0):** render a sibling fixed-width column next to
   the textarea; derive line numbers from the model buffer, vertical offset from the
   textarea's `value`, line height from the same tokens (`widgetTextInputSize` ×
   line-height rule). Wire `on_scroll` → Msg → store `value` in model → both widgets
   rebuild in lockstep. Draw a caret-line highlight in the gutter from
   `textGeometryForWidget(...).caret_bounds`. Exit criteria: no visible drift during
   wheel scroll, kinetic scroll, PageUp/Down, and edits that change line count;
   IME composition does not desync.
2. **Monaco-in-WebView spike (2–4 days):** scene declares a `.webview` view parented
   to the canvas view; `UiApp.Options.web_panes` anchors it to an
   `editor-pane`-labelled panel widget. Load Monaco from a bundled asset URL. Editor→
   model messages via bridge `invoke` (async handlers → Msg dispatch), model→editor via
   `emitWindowEvent` + `zero.on`. Exit criteria (these are the documented unknowns, not
   missing primitives): focus handoff canvas↔webview both directions; Cmd/Ctrl
   shortcuts not swallowed; IME works inside the pane on Linux WebKitGTK; pane
   tracks anchor frame during window resize and split drags at 60 fps; teardown on
   tab close leaks nothing.

Syntax highlighting inside a native textarea is BLOCKED on SDK span support in
text-input widgets — if track 2 fails, that is the exact upstream unblock criterion.

### Blocker 2 — LSP streamed child processes: **SPIKE** (sidecar broker)

**(a) 0.4.0 support:** partial. Long-lived children with streamed stdout: yes.
Bidirectional: no — stdin is one-shot ≤4 KiB, and `.lines` framing cannot carry
Content-Length-framed bodies (no trailing newline guarantee).

**(b) 0.4.2:** no change (`effects.zig` identical).

**(c) Recommendation — SPIKE the broker architecture (3–5 days):**

- Broker = a tiny helper process the app `spawn`s (for the spike: `python3` script;
  for production: a small Zig 0.16 binary built with the already-present
  `~/.native/toolchains/zig-0.16.0/zig` and shipped as an app asset).
- Broker owns the language-server child (full stdio pipes, process tree ownership).
- **Server→app:** broker converts each Content-Length message to one NDJSON line on
  its own stdout → app receives via spawn `.lines` with
  `max_line_bytes = 256 KiB` (`max_effect_line_bytes_ceiling`); larger payloads
  (rare: huge publishDiagnostics) chunk across lines with a seq header.
  This path is event-driven (real `wake_fn` wakeups, no polling).
- **App→server:** broker listens on `127.0.0.1:<ephemeral>` (prints the port as its
  first stdout line); app sends each client→server message as `fetch` POST
  (64 KiB payload cap → chunk `didOpen` for big files, or prefer incremental
  `didChange`). Existing `src/lsp/jsonrpc.zig` framing/session scaffold plugs in
  unchanged above this transport.
- Lifecycle: `cancel(key)` on the broker spawn kills the tree; broker exit delivers
  `.on_exit` → Process Governor integration for free.
- Exit criteria: zls or typescript-language-server round-trips initialize →
  didOpen → publishDiagnostics → hover over a 30-minute session with no dropped
  lines (`dropped_before == 0`), cancel tears down the whole tree, and p95
  request→response overhead added by the hop is < 10 ms.
- Verify first: whether `fetch` requires adding `network` to `app.zon` permissions.

Fallback (no broker): in-process thread + `std.process` pipes + mutex ring drained by
a repeating Effects timer (8–16 ms). Legal, but loses process-tree ownership and adds
poll latency — treat as plan B.

### Blocker 3 — Cross-platform PTY terminal: **SPIKE** (same sidecar), Linux-first

**(a) 0.4.0 support:** none. No PTY API anywhere in the SDK.

**(b) 0.4.2:** none.

**(c) Recommendation — SPIKE reusing the Blocker-2 broker (2–3 days incremental):**

- Broker variant owns the PTY: `openpty`+`fork` (Linux/macOS), exec `$SHELL`;
  emits PTY output as base64-in-JSON NDJSON lines (spawn `.lines` — output is not
  newline-safe raw); accepts input and `resize {cols, rows}` via localhost POST.
- App side plugs into the existing bounded ring / input queue / resize scaffolds in
  `src/terminal/` (currently `unavailable`, `pty_session.zig:14`).
- Windows needs a ConPTY broker later — out of spike scope; Linux+macOS prove the
  architecture. Exit criteria: interactive `htop`/`vim` usable, resize propagates,
  Ctrl-C reaches the foreground process group, 60 fps output bursts don't exceed the
  64-entry completion queue without visible `dropped_before` (tune with output
  coalescing in the broker, e.g. 8 ms flush).
- Keystroke latency note: input POSTs are one `fetch` slot each; coalesce keystrokes
  in-flight (max 16 concurrent effects shared with everything else — budget ~4 for
  the terminal).

---

## 5. SDK upgrade assessment

Recommend **staying on 0.4.0 for now** and revisiting after the WebView spike:

- 0.4.1/0.4.2 add zero capability for any blocker (effects/api byte-identical).
- Compatibility risk of upgrading is low (patch releases; changes confined to canvas
  rendering internals, webview hosts, branding) but non-zero: canvas
  `binary_packet_version` 3→4 and pixel-snap changes could shift golden/screenshot
  fixtures under `apps/native-shell/fixtures/`, and the 252-test suite should be
  re-run. The macOS/Windows webview host fixes become the concrete reason to upgrade
  when (and only when) the Monaco pane ships beyond Linux.
- If upgraded: bump the pin, `npm install` under `.tools/`, re-run
  `npm run check && npm test && npm run build`, and re-record any changed canvas
  fixtures in one commit.
