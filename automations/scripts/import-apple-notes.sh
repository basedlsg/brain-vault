#!/bin/zsh
# Brain Vault — one-shot Apple Notes importer.
#
# Pulls every Apple Note (across all accounts) into archive/apple-notes/
# as individual markdown files with frontmatter capturing:
#   - original title
#   - creation date
#   - modification date
#   - account (iCloud, On My Mac, Exchange, etc.)
#   - folder name
#
# Run once to backfill. Apple Notes makes a poor ongoing capture path
# (sync delays, no API, lossy formatting); use the iOS Shortcut for
# new captures instead.
#
# Requires: macOS, AppleScript permissions for Notes.app on first run.

set -euo pipefail

VAULT="/Users/carlos/Brain/OBSIDIAN"
DEST="$VAULT/archive/apple-notes"
LOG="$VAULT/automations/scripts/logs/apple-notes-import.log"

mkdir -p "$DEST"
mkdir -p "$VAULT/automations/scripts/logs"

echo "=== Apple Notes import — $(date) ===" > "$LOG"
echo "Destination: $DEST" >> "$LOG"

# Use osascript to extract notes. Output is a tab-separated stream of
# [name][TAB][creation-date][TAB][mod-date][TAB][account][TAB][folder][TAB][body]
# with embedded newlines/tabs in the body replaced first.
echo "→ Asking Notes.app for the inventory (you may see a permission prompt the first time)..." | tee -a "$LOG"

osascript <<'APPLESCRIPT' > /tmp/apple-notes-export.tsv
tell application "Notes"
    set output to ""
    set noteList to every note
    repeat with n in noteList
        try
            set noteName to (name of n) as string
            set noteCreated to (creation date of n) as string
            set noteMod to (modification date of n) as string
            set noteAccount to (name of (account of n)) as string
            try
                set noteFolder to (name of (container of n)) as string
            on error
                set noteFolder to "(no folder)"
            end try
            set noteBody to (body of n) as string
            -- Replace control chars in body so the TSV stays parseable.
            -- ASCII unit separator (\037) inside body becomes a paragraph break.
            set AppleScript's text item delimiters to {return & linefeed, linefeed, return}
            set bodyParts to text items of noteBody
            set AppleScript's text item delimiters to (ASCII character 31)
            set noteBodyFlat to bodyParts as string
            set AppleScript's text item delimiters to ""

            set output to output & noteName & tab & noteCreated & tab & noteMod & tab & noteAccount & tab & noteFolder & tab & noteBodyFlat & linefeed
        on error errMsg
            -- skip notes we can't read
        end try
    end repeat
    return output
end tell
APPLESCRIPT

NOTE_COUNT=$(wc -l < /tmp/apple-notes-export.tsv | xargs)
echo "→ Got $NOTE_COUNT notes from Notes.app" | tee -a "$LOG"

if (( NOTE_COUNT == 0 )); then
  echo "ERROR: no notes returned. Check Notes.app permissions:" | tee -a "$LOG"
  echo "  System Settings → Privacy & Security → Automation → grant Terminal access to Notes." | tee -a "$LOG"
  exit 1
fi

# Process each note into a markdown file
WRITTEN=0
SKIPPED=0
while IFS=$'\t' read -r name created mod account folder body; do
  [[ -z "$name" ]] && { ((SKIPPED++)); continue; }

  # Slug from name
  slug=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | head -c 50)
  [[ -z "$slug" ]] && slug="untitled"

  # Convert AppleScript date "Tuesday, March 14, 2023 at 2:42:18 PM" → "2023-03-14"
  iso_created=$(date -j -f "%A, %B %d, %Y at %I:%M:%S %p" "$created" "+%Y-%m-%d" 2>/dev/null || echo "unknown")
  iso_mod=$(date -j -f "%A, %B %d, %Y at %I:%M:%S %p" "$mod" "+%Y-%m-%d" 2>/dev/null || echo "unknown")

  # Filename
  filename="$iso_created-$slug.md"
  dest="$DEST/$filename"

  # Avoid collision
  if [[ -f "$dest" ]]; then
    filename="$iso_created-$slug-$(date +%s%N | tail -c 6).md"
    dest="$DEST/$filename"
  fi

  # Restore paragraph breaks (ASCII 31 → \n\n) and strip basic HTML
  body_md=$(echo "$body" | sed $'s/\037/\\\n\\\n/g' | python3 -c "
import sys, re, html
text = sys.stdin.read()
# Decode HTML entities
text = html.unescape(text)
# Strip tags
text = re.sub(r'<[^>]+>', '', text)
# Collapse 3+ newlines to 2
text = re.sub(r'\n{3,}', '\n\n', text)
print(text.strip())
" 2>/dev/null || echo "$body")

  # Sanitize the title for YAML
  yaml_title=$(echo "$name" | sed 's/"/\\"/g')
  yaml_account=$(echo "$account" | sed 's/"/\\"/g')
  yaml_folder=$(echo "$folder" | sed 's/"/\\"/g')

  cat > "$dest" <<EOF
---
type: apple-note
source: apple-notes
original_date: $iso_created
modification_date: $iso_mod
imported_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
account: "$yaml_account"
folder: "$yaml_folder"
title: "$yaml_title"
---

# $name

$body_md
EOF
  ((WRITTEN++))
done < /tmp/apple-notes-export.tsv

rm -f /tmp/apple-notes-export.tsv

echo "" | tee -a "$LOG"
echo "✓ Wrote $WRITTEN notes to $DEST" | tee -a "$LOG"
echo "  Skipped $SKIPPED empty/unreadable" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "Open the folder in Obsidian. The import preserves Apple Notes' original" | tee -a "$LOG"
echo "creation dates in frontmatter (original_date) — the weekly synthesis will" | tee -a "$LOG"
echo "use that to anchor when each note actually came from." | tee -a "$LOG"
