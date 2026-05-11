#!/bin/zsh
# Spotify recently-played sync — pulls the last 50 tracks daily and writes
# inbox/listening/YYYY-MM-DD-spotify.md (Markdown table).
#
# Schedule: daily 23:00 via launchd com.carlos.brain.sync-spotify.

set -euo pipefail
setopt NULL_GLOB 2>/dev/null || true

VAULT="/Users/carlos/Brain/OBSIDIAN"
DEST="$VAULT/inbox/listening"
LOG="$VAULT/automations/scripts/logs/spotify-sync.log"
mkdir -p "$DEST" "$VAULT/automations/scripts/logs"

[[ -f "$HOME/.brain-secrets" ]] && { set -a; source "$HOME/.brain-secrets"; set +a; }
if [[ -z "${SPOTIFY_REFRESH_TOKEN:-}" || -z "${SPOTIFY_CLIENT_ID:-}" || -z "${SPOTIFY_CLIENT_SECRET:-}" ]]; then
  echo "Spotify not configured. Run spotify-auth.sh first." >&2
  exit 1
fi

{
  echo "=== Spotify sync — $(date) ==="
} >> "$LOG"

TOKEN_RESP=$(curl -sS -X POST https://accounts.spotify.com/api/token \
  -u "$SPOTIFY_CLIENT_ID:$SPOTIFY_CLIENT_SECRET" \
  -d "grant_type=refresh_token" \
  -d "refresh_token=$SPOTIFY_REFRESH_TOKEN")

ACCESS=$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')
if [[ -z "$ACCESS" ]]; then
  echo "ERROR: refresh failed:" | tee -a "$LOG"
  echo "$TOKEN_RESP" | jq | tee -a "$LOG"
  exit 1
fi

NEW_REFRESH=$(echo "$TOKEN_RESP" | jq -r '.refresh_token // empty')
if [[ -n "$NEW_REFRESH" && "$NEW_REFRESH" != "$SPOTIFY_REFRESH_TOKEN" ]]; then
  /usr/bin/sed -i '' "s|^SPOTIFY_REFRESH_TOKEN=.*|SPOTIFY_REFRESH_TOKEN=\"$NEW_REFRESH\"|" "$HOME/.brain-secrets"
  echo "Refresh token rotated, saved." >> "$LOG"
fi

DATE=$(date +%Y-%m-%d)
OUT="$DEST/$DATE-spotify.md"

RESP=$(curl -sS -H "Authorization: Bearer $ACCESS" \
  "https://api.spotify.com/v1/me/player/recently-played?limit=50")

if ! echo "$RESP" | jq -e '.items' >/dev/null 2>&1; then
  echo "ERROR: recently-played failed:" | tee -a "$LOG"
  echo "$RESP" | jq | tee -a "$LOG"
  exit 1
fi

COUNT=$(echo "$RESP" | jq '.items | length')
echo "Got $COUNT recently-played items" >> "$LOG"

if (( COUNT == 0 )); then
  echo "Nothing played today. Skipping write." | tee -a "$LOG"
  exit 0
fi

{
  echo "---"
  echo "type: listening"
  echo "source: spotify"
  echo "captured_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "track_count: $COUNT"
  echo "---"
  echo
  echo "# Spotify — $DATE"
  echo
  echo "$COUNT tracks played in the last ~24 hours (Spotify's recently-played cap)."
  echo
  echo "| Time | Track | Artist | Album |"
  echo "|---|---|---|---|"
  echo "$RESP" | jq -r '.items | sort_by(.played_at) | reverse | .[] |
    "| \(.played_at | sub("T"; " ") | sub("\\..*$"; "") | sub("Z"; "")) | \(.track.name | gsub("\\|";"/")) | \(.track.artists[0].name | gsub("\\|";"/")) | \(.track.album.name | gsub("\\|";"/")) |"'
  echo
  echo "## Top artists this session (by play count)"
  echo
  echo "$RESP" | jq -r '
    [.items[].track.artists[0].name] | group_by(.) |
    map({artist: .[0], n: length}) | sort_by(.n) | reverse |
    .[] | "- **\(.artist)** — \(.n) play\(if .n>1 then "s" else "" end)"'
} > "$OUT"

echo "Wrote $OUT ($COUNT tracks)" | tee -a "$LOG"
