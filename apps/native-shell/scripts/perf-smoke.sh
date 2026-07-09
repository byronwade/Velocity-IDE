#!/usr/bin/env bash
# Placeholder performance smoke for Velocity native shell.
# Real marks land once native timing hooks are wired.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "velocity perf-smoke (placeholder)"
echo "app_root=$ROOT"
echo "app_start_ms=42"
echo "first_window_ms=118"
echo "first_paint_ms=186"
echo "command_palette_open_ms=8"
echo "terminal_open_ms=12"
echo "memory_rss_mb=48"
echo "loaded_plugins_count=0"
echo "note: values are mock until instrumentation is connected"
