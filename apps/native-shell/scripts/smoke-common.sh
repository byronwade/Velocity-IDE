#!/usr/bin/env bash

smoke_wait_for_app() {
  local app_pid="$1"
  local log_file="$2"
  local snapshot=""
  local attempt=0

  if native automate wait; then
    while test "$attempt" -lt 60; do
      if ! kill -0 "$app_pid" 2>/dev/null; then
        break
      fi
      snapshot="$(native automate snapshot 2>/dev/null || true)"
      if printf '%s\n' "$snapshot" | grep -Eq 'role=(button|listitem|textbox)'; then
        return 0
      fi
      attempt=$((attempt + 1))
      sleep 0.5
    fi
  fi

  printf 'smoke: app did not present an interactive frame; last snapshot follows\n' >&2
  if test -n "$snapshot"; then
    printf '%s\n' "$snapshot" >&2
  fi
  printf 'smoke: app log follows (%s)\n' "$log_file" >&2
  if test -r "$log_file"; then
    awk '{ print }' "$log_file" >&2
  else
    printf 'smoke: app log is unavailable\n' >&2
  fi
  if ! kill -0 "$app_pid" 2>/dev/null; then
    printf 'smoke: app process %s exited before automation became ready\n' "$app_pid" >&2
  fi
  return 1
}
