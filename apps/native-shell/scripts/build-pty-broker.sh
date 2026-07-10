#!/usr/bin/env bash
# Build the PTY sidecar broker binary. The app's `native build` does not
# support a second executable target yet, so the broker is built directly
# with zig into the same zig-out/bin the app model probes
# (src/terminal/pty_runtime.zig: broker_build_rel_path).
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SHELL_ROOT"

ZIG="${ZIG:-$HOME/.native/toolchains/zig-0.16.0/zig}"
if ! test -x "$ZIG"; then
  echo "build-pty-broker: zig toolchain not found at $ZIG (set ZIG=...)" >&2
  exit 1
fi

mkdir -p zig-out/bin
"$ZIG" build-exe sidecar/pty_broker.zig -O ReleaseSafe -femit-bin=zig-out/bin/velocity-pty-broker
rm -f zig-out/bin/velocity-pty-broker.o
echo "build-pty-broker: ok -> zig-out/bin/velocity-pty-broker"
