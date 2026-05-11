#!/bin/zsh
# Apple Notes delta sync — pulls notes modified since last successful run.
# Run via launchd hourly. First run after the initial 4682-note import will
# be fast — only changes since then. Each subsequent run only sees deltas.

set -euo pipefail
setopt NULL_GLOB 2>/dev/null || true

VAULT="/Users/carlos/Brain/OBSIDIAN"
DEST="$VAULT/archive/apple-notes"
SINCE_FILE="$DEST/.last-sync"
LOG="$VAULT/automations/scripts/logs/apple-notes-sync.log"
JXA="$VAULT/automations/scripts/_apple-notes-delta.js"
mkdir -p "$DEST" "$VAULT/automations/scripts/logs"

SINCE_MS=0
if [[ -f "$SINCE_FILE" ]]; then
  SINCE_MS=$(cat "$SINCE_FILE" 2>/dev/null | tr -d '[:space:]')
  [[ -z "$SINCE_MS" || "$SINCE_MS" =~ [^0-9] ]] && SINCE_MS=0
fi

{
  echo "=== Apple Notes sync — $(date) ==="
  echo "Since: $SINCE_MS ms"
} >> "$LOG"

if ! osascript -l JavaScript -e 'Application("Notes").notes.length' >/dev/null 2>&1; then
  echo "Notes.app not accessible. Skipping." >> "$LOG"
  exit 0
fi

result=$(osascript -l JavaScript "$JXA" "$DEST" "$SINCE_MS" 2>>"$LOG")
echo "  $result" >> "$LOG"

new_count=$(echo "$result" | jq -r '.writtenNew // 0')
updated_count=$(echo "$result" | jq -r '.updated // 0')
max_mod=$(echo "$result" | jq -r '.maxModMs // 0')

if [[ "$max_mod" =~ ^[0-9]+$ ]] && (( max_mod > SINCE_MS )); then
  echo "$max_mod" > "$SINCE_FILE"
fi

if (( new_count > 0 || updated_count > 0 )); then
  echo "delta sync: $new_count new + $updated_count updated" >> "$LOG"
fi
