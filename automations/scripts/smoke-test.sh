#!/bin/zsh
# Brain Vault — smoke test
# Verifies the LLM round-trip works end-to-end against the actual vault.
# Supports either Anthropic (default) or DeepSeek (set BRAIN_LLM=deepseek).
# Writes a real daily-brief to /daily-briefs.
#
# Usage:
#   # Anthropic (outside China):
#   export ANTHROPIC_API_KEY=sk-ant-...
#   ./automations/scripts/smoke-test.sh
#
#   # DeepSeek (works from China):
#   export BRAIN_LLM=deepseek
#   export DEEPSEEK_API_KEY=sk-...
#   ./automations/scripts/smoke-test.sh

set -euo pipefail

VAULT="/Users/carlos/Brain"
[[ -d "$VAULT/inbox" ]] || { echo "ERROR: vault not at $VAULT" >&2; exit 1; }

LLM="${BRAIN_LLM:-anthropic}"

case "$LLM" in
  anthropic)
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
      echo "ERROR: ANTHROPIC_API_KEY not set." >&2; exit 1
    fi
    API_URL="https://api.anthropic.com/v1/messages"
    MODEL="claude-opus-4-7"
    ;;
  deepseek)
    if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
      echo "ERROR: DEEPSEEK_API_KEY not set." >&2; exit 1
    fi
    API_URL="https://api.deepseek.com/chat/completions"
    MODEL="deepseek-chat"
    ;;
  moonshot|kimi)
    if [[ -z "${MOONSHOT_API_KEY:-}" ]]; then
      echo "ERROR: MOONSHOT_API_KEY not set." >&2; exit 1
    fi
    API_URL="https://api.moonshot.cn/v1/chat/completions"
    MODEL="kimi-k2-0905-preview"
    ;;
  *)
    echo "ERROR: BRAIN_LLM must be one of: anthropic, deepseek, moonshot. Got: $LLM" >&2; exit 1
    ;;
esac

DATE=$(date +%Y-%m-%d)
OUT="$VAULT/daily-briefs/brief-$DATE.md"

echo "→ Provider: $LLM ($MODEL)"
echo "→ Reading vault slice…"
VAULT_SLICE=$(
  echo "=== CLAUDE.md ==="; cat "$VAULT/CLAUDE.md" 2>/dev/null || true
  echo "=== INBOX ==="; find "$VAULT/inbox" -type f -name '*.md' -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== NOTES ==="; find "$VAULT/notes" -type f -name '*.md' -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== IDEAS ==="; find "$VAULT/ideas" -type f -name '*.md' -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
)

SLICE_SIZE=$(echo "$VAULT_SLICE" | wc -c | xargs)
echo "→ Vault slice: $SLICE_SIZE chars"

USER_PROMPT="Three things from the vault below: 1) CONNECTIONS — 3 specific cross-note links, quote both sides with filenames. 2) PATTERN — one. 3) QUESTION — one, not a task.

Format as:
# Daily brief — $DATE
## Connections
## Pattern
## Question

If the vault is too thin to give a real brief, say so plainly under each heading.

VAULT:

$VAULT_SLICE"

SYSTEM_PROMPT="You are reading Carlos's Brain vault. Output ONLY valid markdown — no preamble, no code fences around the whole thing."

if [[ "$LLM" == "anthropic" ]]; then
  PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg user "$USER_PROMPT" \
    '{
      model: $model,
      max_tokens: 4000,
      system: $system,
      messages: [{ role: "user", content: $user }]
    }')
  HEADERS=(-H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01")
  EXTRACT='.content[0].text'
else
  KEY_VAR="${LLM:u}_API_KEY"
  KEY_VAL="${(P)KEY_VAR}"
  PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg user "$USER_PROMPT" \
    '{
      model: $model,
      max_tokens: 4000,
      messages: [
        { role: "system", content: $system },
        { role: "user", content: $user }
      ]
    }')
  HEADERS=(-H "Authorization: Bearer $KEY_VAL")
  EXTRACT='.choices[0].message.content'
fi

echo "→ Calling $LLM…"
RESP=$(curl -sS "$API_URL" \
  "${HEADERS[@]}" \
  -H "content-type: application/json" \
  -d "$PAYLOAD")

if echo "$RESP" | jq -e '.error' >/dev/null 2>&1; then
  echo "ERROR from $LLM API:" >&2
  echo "$RESP" | jq '.error' >&2
  exit 1
fi

CONTENT=$(echo "$RESP" | jq -r "$EXTRACT")
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
provider: $LLM
model: $MODEL
---

$CONTENT
EOF

echo ""
echo "✓ Wrote $OUT"
echo ""
echo "Open it in Obsidian. If it reads like a real brief — the LLM can talk to your vault and you're ready to wire up the schedule. If it complains the vault is too thin, that's expected on day 1."
