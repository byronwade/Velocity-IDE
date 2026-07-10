#!/usr/bin/env bash
# Build the LSP sidecar broker binary. The app's `native build` does not
# support a second executable target yet, so the broker is built directly
# with zig into the same zig-out/bin the app model probes
# (src/lsp/lsp_session.zig: broker_build_rel_path).
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SHELL_ROOT"

ZIG="${ZIG:-$HOME/.native/toolchains/zig-0.16.0/zig}"
if ! test -x "$ZIG"; then
  echo "build-lsp-broker: zig toolchain not found at $ZIG (set ZIG=...)" >&2
  exit 1
fi

mkdir -p zig-out/bin
"$ZIG" build-exe sidecar/lsp_broker.zig -O ReleaseSafe -femit-bin=zig-out/bin/velocity-lsp-broker
rm -f zig-out/bin/velocity-lsp-broker.o
echo "build-lsp-broker: ok -> zig-out/bin/velocity-lsp-broker"
