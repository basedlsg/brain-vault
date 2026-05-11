#!/bin/zsh
# Browser history sync — Brave + Safari (when FDA granted).
#
# Reads each browser's history SQLite, finds URLs visited since last sync,
# dedupes by URL+date, filters out search engine intermediate pages, and
# writes daily summaries to archive/browser-history/YYYY-MM-DD.md.
#
# Safari requires Terminal to have Full Disk Access (System Settings →
# Privacy & Security → Full Disk Access). Brave reads from a different
# path that doesn't need FDA.

set -uo pipefail  # no -e: SIGPIPE from head|awk is OK
setopt NULL_GLOB 2>/dev/null || true

VAULT="/Users/carlos/Brain/OBSIDIAN"
DEST="$VAULT/archive/browser-history"
LOG="$VAULT/automations/scripts/logs/browser-history.log"
SINCE_FILE="$DEST/.last-sync"
mkdir -p "$DEST" "$VAULT/automations/scripts/logs"

BRAVE_DB="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/History"
SAFARI_DB="$HOME/Library/Safari/History.db"

DATE=$(date +%Y-%m-%d)
OUT="$DEST/$DATE.md"

# Default: pull last 24h. Tracked via since file (unix epoch).
NOW=$(date +%s)
SINCE=$(( NOW - 86400 ))
if [[ -f "$SINCE_FILE" ]]; then
  s=$(cat "$SINCE_FILE" 2>/dev/null | tr -d '[:space:]')
  [[ "$s" =~ ^[0-9]+$ ]] && SINCE="$s"
fi

{
  echo "=== Browser history sync — $(date) ==="
  echo "Since: $(date -r $SINCE -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "$LOG"

TMP=$(mktemp)
trap "rm -f $TMP /tmp/brave-history-copy.db" EXIT

# -------- BRAVE --------
BRAVE_COUNT=0
if [[ -r "$BRAVE_DB" ]]; then
  # Brave locks DB while running; copy and read the copy
  if cp "$BRAVE_DB" /tmp/brave-history-copy.db 2>/dev/null; then
    # Chrome/Brave time: microseconds since 1601-01-01
    # Convert: unix_ts = chrome_ts/1000000 - 11644473600
    sqlite3 -separator $'\t' -readonly /tmp/brave-history-copy.db "
      SELECT
        url,
        IFNULL(title, ''),
        last_visit_time/1000000 - 11644473600 AS unix_ts,
        visit_count
      FROM urls
      WHERE last_visit_time/1000000 - 11644473600 > $SINCE
        AND url NOT LIKE 'https://www.google.com/search%'
        AND url NOT LIKE 'https://duckduckgo.com/?q=%'
        AND url NOT LIKE 'https://www.bing.com/search%'
        AND url NOT LIKE 'chrome://%'
        AND url NOT LIKE 'brave://%'
        AND url NOT LIKE 'about:%'
        AND url NOT LIKE 'http://localhost%'
        AND url NOT LIKE 'http://127.0.0.1%'
      ORDER BY last_visit_time DESC
    " 2>>"$LOG" > "$TMP.brave" || true
    BRAVE_COUNT=$(wc -l < "$TMP.brave" 2>/dev/null | xargs || echo 0)
  fi
fi
echo "Brave: $BRAVE_COUNT URLs since $SINCE" >> "$LOG"

# -------- SAFARI --------
SAFARI_COUNT=0
if [[ -r "$SAFARI_DB" ]]; then
  if cp "$SAFARI_DB" /tmp/safari-history-copy.db 2>/dev/null; then
    # Safari time: seconds since 2001-01-01 (CFAbsoluteTime); add 978307200 to get unix
    sqlite3 -separator $'\t' -readonly /tmp/safari-history-copy.db "
      SELECT
        i.url,
        IFNULL(v.title, ''),
        CAST(v.visit_time + 978307200 AS INTEGER) AS unix_ts,
        i.visit_count
      FROM history_items i
      JOIN history_visits v ON v.history_item = i.id
      WHERE v.visit_time + 978307200 > $SINCE
        AND i.url NOT LIKE 'https://www.google.com/search%'
        AND i.url NOT LIKE 'https://duckduckgo.com/?q=%'
        AND i.url NOT LIKE 'https://www.bing.com/search%'
        AND i.url NOT LIKE 'http://localhost%'
        AND i.url NOT LIKE 'http://127.0.0.1%'
      ORDER BY v.visit_time DESC
    " 2>>"$LOG" > "$TMP.safari" || true
    SAFARI_COUNT=$(wc -l < "$TMP.safari" 2>/dev/null | xargs || echo 0)
    rm -f /tmp/safari-history-copy.db
  else
    echo "Safari DB present but unreadable (likely no Full Disk Access)" >> "$LOG"
  fi
fi
echo "Safari: $SAFARI_COUNT URLs since $SINCE" >> "$LOG"

# Combine, dedupe by URL (keep most recent), and group by domain
cat "$TMP.brave" "$TMP.safari" 2>/dev/null | \
  awk -F'\t' '!seen[$1]++ {print}' | \
  sort -t$'\t' -k3 -rn > "$TMP.dedup" || true

TOTAL=$(wc -l < "$TMP.dedup" 2>/dev/null | xargs || echo 0)
echo "Total after dedup: $TOTAL" >> "$LOG"

if (( TOTAL == 0 )); then
  echo "No new history. Skipping write." >> "$LOG"
  echo "$NOW" > "$SINCE_FILE"
  exit 0
fi

# Group by domain in markdown
{
  echo "---"
  echo "type: browser-history"
  echo "source: brave-safari"
  echo "captured_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "since: $(date -r $SINCE -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "url_count: $TOTAL"
  echo "brave_count: $BRAVE_COUNT"
  echo "safari_count: $SAFARI_COUNT"
  echo "---"
  echo
  echo "# Browser history — $DATE"
  echo
  echo "_$TOTAL distinct URLs since $(date -r $SINCE -u '+%Y-%m-%d %H:%M UTC'). Synthesis can grep this folder by domain or keyword._"
  echo
  echo "## By domain (top 30)"
  echo
  awk -F'\t' '{
    n = split($1, parts, "/")
    if (n >= 3) {
      domain = parts[3]
      sub(/^www\./, "", domain)
      count[domain]++
    }
  } END {
    for (d in count) print count[d] "\t" d
  }' "$TMP.dedup" | sort -rn | head -30 | awk -F'\t' '{ printf "- **%s** (%s)\n", $2, $1 }'
  echo
  echo "## All visits (newest first)"
  echo
  awk -F'\t' '{
    ts = $3
    cmd = "date -r " ts " +%H:%M"
    cmd | getline t
    close(cmd)
    title = ($2 == "") ? "(no title)" : $2
    if (length(title) > 100) title = substr(title, 1, 100) "…"
    printf "- %s · [%s](%s)\n", t, title, $1
  }' "$TMP.dedup" | head -200
  if (( TOTAL > 200 )); then
    echo
    echo "_(showing 200 of $TOTAL — grep the source for older)_"
  fi
} > "$OUT"

echo "Wrote $OUT" >> "$LOG"
echo "$NOW" > "$SINCE_FILE"
