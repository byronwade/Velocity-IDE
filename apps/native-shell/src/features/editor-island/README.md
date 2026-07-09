# Editor Island

- **id:** `feature.editor-island`
- **mode:** `core`
- **status:** `prototype` — typed integration scaffold; rich backends blocked by SDK
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `32`
- **maxProcesses:** `0`
- **activation:** `onFileOpen`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.

## Honest boundary

`bridge/editor_island.zig` defines bounded backend, command, state, selection,
revision, and event types. The current `<textarea>` path remains the only
available backend; this protocol does not host Monaco or change runtime
behavior.

Monaco/WebView is unblocked only when the SDK has a stable embedded WebView
lifecycle and bidirectional messaging plus documented focus, keyboard, IME,
and accessibility forwarding. Native textarea line gutters also remain
blocked: the SDK has no stable gutter/decoration API or caret/scroll
synchronization contract. A supported custom editor surface could unblock it.
