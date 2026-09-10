#!/usr/bin/env bash
# Writes one word (idle/running/waiting) to ~/fukuro-chan/state.txt for the
# fukuro-chan desktop pet to read. Never reads conversation content, never
# blocks the calling Claude Code hook (always exits 0).

STATE_DIR="$HOME/fukuro-chan"
STATE_FILE="$STATE_DIR/state.txt"

write_state() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  printf '%s' "$1" > "$STATE_FILE.tmp" 2>/dev/null && mv -f "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null
}

mode="${1:-idle}"

if [ "$mode" = "notification" ]; then
  payload="$(cat 2>/dev/null)"
  notification_type="$(printf '%s' "$payload" | sed -n 's/.*"notification_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  if [ "$notification_type" = "permission_prompt" ]; then
    write_state "waiting"
  fi
else
  write_state "$mode"
fi

exit 0
