#!/bin/zsh
# Brain Vault — daily brief runner.
# Invoked by launchd at 06:00 weekdays. Runs Claude Code in print mode
# against the daily-brief prompt. Writes daily-briefs/brief-YYYY-MM-DD.md.

set -euo pipefail

VAULT="/Users/carlos/Brain"
CLAUDE_BIN="/Users/carlos/.nvm/versions/node/v20.9.0/bin/claude"
LOG_DIR="$VAULT/automations/scripts/logs"
mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
LOG="$LOG_DIR/daily-brief-$DATE.log"

# Make sure node is in PATH so claude CLI can spawn its own subprocess if needed
export PATH="/Users/carlos/.nvm/versions/node/v20.9.0/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

cd "$VAULT"

PROMPT_FILE="$VAULT/automations/prompts/daily-brief.md"
if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "ERROR: prompt file missing: $PROMPT_FILE" | tee -a "$LOG"
  exit 1
fi

PROMPT="$(cat "$PROMPT_FILE")"

{
  echo "=== Brain daily brief — $(date) ==="
  echo "Vault: $VAULT"
  echo "Claude: $CLAUDE_BIN"
  echo
} >> "$LOG"

# --print: non-interactive, prints final response and exits.
# --dangerously-skip-permissions: required for headless run; the prompt itself
#   constrains writes to daily-briefs/brief-YYYY-MM-DD.md.
"$CLAUDE_BIN" \
  --print \
  --dangerously-skip-permissions \
  "$PROMPT" \
  >> "$LOG" 2>&1

echo "=== Done $(date) ===" >> "$LOG"
