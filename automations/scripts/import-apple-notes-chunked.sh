#!/bin/zsh
# Brute-force Apple Notes importer — chunked, with progress.
# Calls _apple-notes-import.js per chunk so we can show progress between chunks.
# Each note is written to disk inside the JXA loop (no string accumulation).
#
# For 4,682 notes at ~300-500ms/note, expect 25-40 minutes total.
# Safe to interrupt and resume — uses dated filenames + collision suffixes.
#
# Env:
#   START=0      starting note index (default 0)
#   CHUNK=200    notes per JXA invocation (default 200)
#   END=         stop at this index (default: total)

set -euo pipefail
setopt NULL_GLOB 2>/dev/null || true

VAULT="/Users/carlos/Brain/OBSIDIAN"
DEST="$VAULT/archive/apple-notes"
LOG="$VAULT/automations/scripts/logs/apple-notes-import.log"
JXA_SCRIPT="$VAULT/automations/scripts/_apple-notes-import.js"
mkdir -p "$DEST" "$VAULT/automations/scripts/logs"

CHUNK=${CHUNK:-200}
START=${START:-0}

TOTAL=$(osascript -l JavaScript -e 'Application("Notes").notes.length' 2>/dev/null || echo "0")
END=${END:-$TOTAL}

{
  echo "=== Apple Notes chunked import — $(date) ==="
  echo "Total in Notes.app: $TOTAL"
  echo "Range: $START..$END (chunk size $CHUNK)"
  echo
} | tee "$LOG"

if (( TOTAL == 0 )); then
  echo "ERROR: Notes.app returned 0 notes. Is Notes.app open?" | tee -a "$LOG"
  exit 1
fi

if [[ ! -f "$JXA_SCRIPT" ]]; then
  echo "ERROR: missing $JXA_SCRIPT" | tee -a "$LOG"; exit 1
fi

start_ts=$(date +%s)
i=$START
while (( i < END )); do
  chunk_end=$(( i + CHUNK ))
  (( chunk_end > END )) && chunk_end=$END
  pre=$(ls "$DEST"/*.md 2>/dev/null | wc -l | xargs)
  echo "→ chunk: notes $i..$((chunk_end - 1))  (already on disk: $pre)" | tee -a "$LOG"
  result=$(osascript -l JavaScript "$JXA_SCRIPT" "$DEST" "$i" "$chunk_end" 2>&1 | tail -10)
  echo "  $result" | tee -a "$LOG"
  post=$(ls "$DEST"/*.md 2>/dev/null | wc -l | xargs)
  delta=$(( post - pre ))
  elapsed=$(( $(date +%s) - start_ts ))
  echo "  → wrote $delta this chunk; total on disk: $post; elapsed: ${elapsed}s" | tee -a "$LOG"
  i=$chunk_end
done

echo "" | tee -a "$LOG"
final=$(ls "$DEST"/*.md 2>/dev/null | wc -l | xargs)
echo "✓ Done. $final notes in $DEST" | tee -a "$LOG"
echo "Total elapsed: $(( $(date +%s) - start_ts ))s" | tee -a "$LOG"
