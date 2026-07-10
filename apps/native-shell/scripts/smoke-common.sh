#!/usr/bin/env bash

smoke_wait_for_app() {
  local app_pid="$1"
  local log_file="$2"

  if native automate wait; then
    if kill -0 "$app_pid" 2>/dev/null; then
      return 0
    fi
    printf 'smoke: app process %s exited after automation became ready\n' "$app_pid" >&2
    return 1
  fi

  printf 'smoke: automation readiness failed; app log follows (%s)\n' "$log_file" >&2
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
