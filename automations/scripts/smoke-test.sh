#!/bin/zsh
# Brain Vault — smoke test
# Verifies the Anthropic API call works end-to-end against the actual vault
# before you spend any time on N8N. Writes a real daily-brief to /daily-briefs.
#
# Usage:
#   export ANTHROPIC_API_KEY=sk-ant-...
#   ./automations/scripts/smoke-test.sh

set -euo pipefail

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ERROR: ANTHROPIC_API_KEY not set." >&2
  echo "  export ANTHROPIC_API_KEY=sk-ant-..." >&2
  exit 1
fi

VAULT="/Users/carlos/Brain"
[[ -d "$VAULT/inbox" ]] || { echo "ERROR: vault not at $VAULT" >&2; exit 1; }

DATE=$(date +%Y-%m-%d)
OUT="$VAULT/daily-briefs/brief-$DATE.md"

echo "→ Reading vault slice…"
VAULT_SLICE=$(
  echo "=== CLAUDE.md ==="; cat "$VAULT/CLAUDE.md" 2>/dev/null || true
  echo "=== INBOX ==="; find "$VAULT/inbox" -type f -name '*.md' -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== NOTES ==="; find "$VAULT/notes" -type f -name '*.md' -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== IDEAS ==="; find "$VAULT/ideas" -type f -name '*.md' -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
)

SLICE_SIZE=$(echo "$VAULT_SLICE" | wc -c | xargs)
echo "→ Vault slice: $SLICE_SIZE chars"

echo "→ Calling Claude…"
PAYLOAD=$(jq -n \
  --arg slice "$VAULT_SLICE" \
  --arg date "$DATE" \
  '{
    model: "claude-opus-4-7",
    max_tokens: 4000,
    system: "You are reading Carlos Brain vault. Output ONLY valid markdown — no preamble, no code fences around the whole thing.",
    messages: [{
      role: "user",
      content: ("Three things from the vault below: 1) CONNECTIONS — 3 specific cross-note links, quote both sides with filenames. 2) PATTERN — one. 3) QUESTION — one, not a task.\n\nFormat as:\n# Daily brief — " + $date + "\n## Connections\n## Pattern\n## Question\n\nIf the vault is too thin to give a real brief, say so plainly under each heading.\n\nVAULT:\n\n" + $slice)
    }]
  }')

RESP=$(curl -sS https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$PAYLOAD")

if echo "$RESP" | jq -e '.error' >/dev/null 2>&1; then
  echo "ERROR from Anthropic API:" >&2
  echo "$RESP" | jq '.error' >&2
  exit 1
fi

CONTENT=$(echo "$RESP" | jq -r '.content[0].text')
if [[ -z "$CONTENT" || "$CONTENT" == "null" ]]; then
  echo "ERROR: empty response. Full payload:" >&2
  echo "$RESP" >&2
  exit 1
fi

cat > "$OUT" <<EOF
---
type: daily-brief
generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
generator: smoke-test-shell
model: claude-opus-4-7
---

$CONTENT
EOF

echo ""
echo "✓ Wrote $OUT"
echo ""
echo "Open it in Obsidian. If it reads like a real brief — Claude can talk to your vault and you're ready to wire up N8N. If it complains the vault is too thin, that's expected on day 1."
