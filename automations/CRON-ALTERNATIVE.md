# Alternative: skip N8N, use cron + a shell script

If you don't want to run N8N, the daily brief and weekly synthesis can run as plain shell scripts triggered by `launchd` (macOS's cron equivalent). The Telegram bot still needs N8N or a small Node service — there's no shell-only path for that.

---

## 1. Daily-brief script

Save as `/Users/carlos/Brain/automations/scripts/daily-brief.sh` (chmod +x).

```bash
#!/bin/zsh
set -euo pipefail

VAULT="/Users/carlos/Brain"
DATE=$(date +%Y-%m-%d)
OUT="$VAULT/daily-briefs/brief-$DATE.md"

VAULT_SLICE=$(
  echo "=== CLAUDE.md ==="; cat "$VAULT/CLAUDE.md"
  echo "=== INBOX (last 24h) ==="; find "$VAULT/inbox" -type f -name '*.md' -mtime -1 -exec echo '--- {} ---' \; -exec cat {} \;
  echo "=== NOTES (last 7d) ==="; find "$VAULT/notes" -type f -name '*.md' -mtime -7 -exec echo '--- {} ---' \; -exec cat {} \;
  echo "=== IDEAS (last 7d) ==="; find "$VAULT/ideas" -type f -name '*.md' -mtime -7 -exec echo '--- {} ---' \; -exec cat {} \;
)

PAYLOAD=$(jq -n \
  --arg slice "$VAULT_SLICE" \
  --arg date "$DATE" \
  '{
    model: "claude-opus-4-7",
    max_tokens: 4000,
    system: "You are reading Carlos Brain vault. Output ONLY valid markdown — no preamble.",
    messages: [{
      role: "user",
      content: ("Three things from the vault slice below: 1) CONNECTIONS (3 specific cross-note links, quote both sides with filenames), 2) PATTERN (one), 3) QUESTION (one, not a task). Format as # Daily brief — " + $date + " then ## Connections / ## Pattern / ## Question. VAULT:\n\n" + $slice)
    }]
  }')

RESP=$(curl -sS https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$PAYLOAD")

CONTENT=$(echo "$RESP" | jq -r '.content[0].text')

cat > "$OUT" <<EOF
---
type: daily-brief
generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
generator: cron-shell
model: claude-opus-4-7
---

$CONTENT
EOF

echo "Wrote $OUT"
```

---

## 2. Weekly-synthesis script

Same shape, swap the find commands and the prompt. See `02-daily-brief.json` and `03-weekly-synthesis.json` for the canonical prompts to copy into the script.

---

## 3. launchd plist

Save as `~/Library/LaunchAgents/com.carlos.brain.daily-brief.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.carlos.brain.daily-brief</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/carlos/Brain/automations/scripts/daily-brief.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>6</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Weekday</key><integer>2</integer><key>Hour</key><integer>6</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>6</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>6</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>6</integer><key>Minute</key><integer>0</integer></dict>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ANTHROPIC_API_KEY</key>
    <string>sk-ant-REPLACE_ME</string>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>StandardOutPath</key>
  <string>/Users/carlos/Brain/automations/scripts/daily-brief.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/carlos/Brain/automations/scripts/daily-brief.err.log</string>
</dict>
</plist>
```

Load it: `launchctl load ~/Library/LaunchAgents/com.carlos.brain.daily-brief.plist`

> **Trade-off:** this path is simpler (no N8N to keep alive) but harder to monitor and edit visually. N8N gives you a UI for changing schedules, prompts, and seeing run history. Pick whichever you'll actually maintain.
