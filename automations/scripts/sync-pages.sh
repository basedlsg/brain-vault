#!/bin/bash
# Pages.app diary sync — extracts text from every .pages file using Pages.app
# AppleScript, and writes archive/pages/<original-mtime-date>-<name>.md.
#
# Tracks per-file mtimes so we only re-extract changed files on subsequent runs.
# Scheduled hourly via com.carlos.brain.sync-pages.
#
# Uses bash not zsh — zsh has a path-lookup-in-subshells quirk that bricks
# basename/date/tr inside command substitutions on this machine.

set -uo pipefail
# Make sure standard utilities are reachable — launchd / disowned subshells
# don't inherit the user's PATH.
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

VAULT="/Users/carlos/Brain/OBSIDIAN"
DEST="$VAULT/archive/pages"
LOG="$VAULT/automations/scripts/logs/pages-sync.log"
STATE_FILE="$DEST/.mtime-state"
mkdir -p "$DEST" "$VAULT/automations/scripts/logs"
touch "$STATE_FILE"

{
  echo "=== Pages sync — $(date) ==="
} >> "$LOG"

# Find all .pages files. Search common spots; skip Trash/cache/system dirs.
# Pages files are zip archives now (file, not dir) — older may be directories.
FILES=$(
  {
    find "$HOME/Library/Mobile Documents/com~apple~Pages/Documents" -maxdepth 4 -iname '*.pages' 2>/dev/null
    find "$HOME/Documents" -maxdepth 6 -iname '*.pages' 2>/dev/null
    find "$HOME/Desktop" -maxdepth 3 -iname '*.pages' 2>/dev/null
  } | grep -Ev '/\.Trash/|/Library/Application Scripts/|/WebKit/' | sort -u
)

if [[ -z "$FILES" ]]; then
  echo "No .pages files found." | tee -a "$LOG"
  exit 0
fi

TOTAL=$(echo "$FILES" | wc -l | xargs)
echo "Found $TOTAL .pages files" | tee -a "$LOG"

# Helper: pull mtime in seconds since epoch (BSD stat)
get_mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }

# Helper: slugify
slugify() {
  echo -n "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | head -c 60
}

# Helper: looks up cached mtime (returns empty if not found)
last_mtime_for() {
  local p="$1"
  if [[ ! -s "$STATE_FILE" ]]; then return 0; fi
  local line
  line=$(grep -F "$p"$'\t' "$STATE_FILE" 2>/dev/null | head -1) || true
  [[ -n "$line" ]] && echo "$line" | awk -F'\t' '{print $2}' || true
}

# Helper: write/update cached mtime
update_mtime() {
  local p="$1"; local m="$2"
  local tmp=$(mktemp)
  grep -v -F "$p"$'\t' "$STATE_FILE" > "$tmp" 2>/dev/null || true
  echo "$p"$'\t'"$m" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
}

NEW=0; UPDATED=0; SKIPPED=0; ERRORED=0

while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  basename=$(basename "$path" .pages)
  cur_mtime=$(get_mtime "$path")
  last=$(last_mtime_for "$path")
  if [[ -n "$last" && "$last" == "$cur_mtime" ]]; then
    SKIPPED=$(( SKIPPED + 1 ))
    continue
  fi

  # Filename date prefix uses the file's mtime (best signal we have for "when written")
  date_prefix=$(date -r "$cur_mtime" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
  slug=$(slugify "$basename")
  out="$DEST/$date_prefix-$slug.md"

  # AppleScript extraction. Quote single quotes inside the heredoc carefully.
  # On success, writes /tmp/page-extract.txt as UTF-8.
  extraction=$(osascript <<APPLESCRIPT 2>&1
tell application "Pages"
  try
    set theDoc to open POSIX file "$path"
    delay 1
    set theText to body text of theDoc
    set txtPath to "/tmp/page-extract-$$.txt"
    set fileRef to open for access POSIX file txtPath with write permission
    set eof of fileRef to 0
    write theText to fileRef as «class utf8»
    close access fileRef
    close theDoc saving no
    return "ok:" & txtPath
  on error errMsg
    return "err:" & errMsg
  end try
end tell
APPLESCRIPT
  )

  if [[ "$extraction" != ok:* ]]; then
    echo "  extract failed for $path: $extraction" >> "$LOG"
    ERRORED=$(( ERRORED + 1 ))
    continue
  fi

  txt_file="${extraction#ok:}"
  body=$(cat "$txt_file" 2>/dev/null)
  rm -f "$txt_file"

  if [[ -z "$body" ]]; then
    echo "  empty body for $path" >> "$LOG"
    SKIPPED=$(( SKIPPED + 1 ))
    continue
  fi

  # Frontmatter + body
  is_new="false"
  [[ ! -f "$out" ]] && is_new="true"

  cat > "$out" <<EOF
---
type: pages-diary
source: pages-app
original_path: "$(echo "$path" | sed 's|"|\\"|g')"
mtime_seen: $cur_mtime
mtime_date: $date_prefix
extracted_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
title: "$basename"
---

# $basename

$body
EOF

  update_mtime "$path" "$cur_mtime"

  if [[ "$is_new" == "true" ]]; then
    NEW=$(( NEW + 1 ))
    echo "  + $out" >> "$LOG"
  else
    UPDATED=$(( UPDATED + 1 ))
    echo "  ~ $out" >> "$LOG"
  fi
done <<< "$FILES"

{
  echo "Pages sync result: new=$NEW updated=$UPDATED skipped=$SKIPPED errored=$ERRORED"
} | tee -a "$LOG"
