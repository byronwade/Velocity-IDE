#!/usr/bin/env bash
# Exercise snippet append/undo and read-only diff review open/close.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="/workspace/.tools/node_modules/.bin:/home/ubuntu/.native/toolchains/zig-0.16.0:${PATH:-}"

native build -Dautomation=true
rm -rf .zig-cache/native-sdk-automation
./zig-out/bin/velocity-ide >/tmp/velocity-review-snippet-smoke.out 2>&1 &
APP_PID=$!
cleanup() {
  kill "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
}
trap cleanup EXIT
sleep 3
kill -0 "$APP_PID"

OPEN_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="acme-dashboard".*/\1/p' | head -1)"
test -n "$OPEN_ID"
native automate widget-click main-canvas "$OPEN_ID"
native automate assert --timeout-ms 5000 'Append a literal snippet at the end of the document'

APPEND_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Append a literal snippet at the end of the document".*/\1/p' | head -1)"
test -n "$APPEND_ID"
native automate widget-click main-canvas "$APPEND_ID"
native automate assert --timeout-ms 5000 'Append Snippet picker' 'Append a fixture component'

SNIPPET_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="Append a fixture component".*/\1/p' | head -1)"
test -n "$SNIPPET_ID"
native automate widget-click main-canvas "$SNIPPET_ID"
native automate assert --timeout-ms 5000 'FixtureSnippet' 'Snippet appended'
native automate shortcut undo_edit
native automate assert --absent --timeout-ms 5000 'FixtureSnippet'

native automate shortcut command_palette
PALETTE_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=textbox name="Command search".*/\1/p' | head -1)"
test -n "$PALETTE_ID"
native automate widget-action main-canvas "$PALETTE_ID" set_text "Compare with Saved"
native automate assert --timeout-ms 5000 'Compare with Saved'
COMPARE_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="Compare with Saved".*/\1/p' | head -1)"
test -n "$COMPARE_ID"
native automate widget-click main-canvas "$COMPARE_ID"
native automate assert --timeout-ms 5000 'Read-only Diff Review' 'Close Diff Review'

CLOSE_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Close Diff Review".*/\1/p' | head -1)"
test -n "$CLOSE_ID"
native automate widget-click main-canvas "$CLOSE_ID"
native automate assert --absent --timeout-ms 5000 'Read-only Diff Review'

echo "review-snippet-smoke: ok"
