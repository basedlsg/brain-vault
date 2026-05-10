#!/bin/zsh
# Brain Vault — weekly synthesis runner.
# Invoked by launchd at Monday 09:00. Runs Claude Code in print mode
# against the weekly-synthesis prompt. Writes weekly-syntheses/synthesis-YYYY-MM-DD.md.

set -euo pipefail

VAULT="/Users/carlos/Brain"
CLAUDE_BIN="/Users/carlos/.nvm/versions/node/v20.9.0/bin/claude"
LOG_DIR="$VAULT/automations/scripts/logs"
mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
LOG="$LOG_DIR/weekly-synthesis-$DATE.log"

export PATH="/Users/carlos/.nvm/versions/node/v20.9.0/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

cd "$VAULT"

PROMPT_FILE="$VAULT/automations/prompts/weekly-synthesis.md"
if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "ERROR: prompt file missing: $PROMPT_FILE" | tee -a "$LOG"
  exit 1
fi

PROMPT="$(cat "$PROMPT_FILE")"

{
  echo "=== Brain weekly synthesis — $(date) ==="
  echo "Vault: $VAULT"
  echo "Claude: $CLAUDE_BIN"
  echo
} >> "$LOG"

"$CLAUDE_BIN" \
  --print \
  --dangerously-skip-permissions \
  "$PROMPT" \
  >> "$LOG" 2>&1

echo "=== Done $(date) ===" >> "$LOG"
