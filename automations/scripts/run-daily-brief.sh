#!/bin/zsh
# Brain Vault — daily brief runner.
# Invoked by launchd at 06:00 weekdays. Reads vault slice, calls an LLM,
# writes daily-briefs/brief-YYYY-MM-DD.md.
#
# Provider is chosen via $BRAIN_LLM (deepseek | moonshot | anthropic).
# API key is read from ~/.brain-secrets (one line per key: KEY=value).
# Default: deepseek (works from China without VPN, cheap, OpenAI-compatible).

set -euo pipefail

VAULT="/Users/carlos/Brain/OBSIDIAN"
LOG_DIR="$VAULT/automations/scripts/logs"
mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
LOG="$LOG_DIR/daily-brief-$DATE.log"
OUT="$VAULT/daily-briefs/brief-$DATE.md"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Load secrets if present
if [[ -f "$HOME/.brain-secrets" ]]; then
  set -a
  source "$HOME/.brain-secrets"
  set +a
fi

cd "$VAULT"

LLM="${BRAIN_LLM:-llama}"

case "$LLM" in
  llama)
    [[ -z "${LLAMA_API_KEY:-}" ]] && { echo "ERROR: LLAMA_API_KEY not set in ~/.brain-secrets" | tee -a "$LOG"; exit 1; }
    API_URL="https://api.llama.com/v1/chat/completions"
    MODEL="${LLAMA_MODEL:-Llama-4-Maverick-17B-128E-Instruct-FP8}"
    AUTH_HEADER="Authorization: Bearer $LLAMA_API_KEY"
    EXTRACT='.completion_message.content.text'
    BODY_FMT="llama"
    ;;
  deepseek)
    [[ -z "${DEEPSEEK_API_KEY:-}" ]] && { echo "ERROR: DEEPSEEK_API_KEY not set in ~/.brain-secrets" | tee -a "$LOG"; exit 1; }
    API_URL="https://api.deepseek.com/chat/completions"
    MODEL="deepseek-chat"
    AUTH_HEADER="Authorization: Bearer $DEEPSEEK_API_KEY"
    EXTRACT='.choices[0].message.content'
    BODY_FMT="openai"
    ;;
  moonshot|kimi)
    [[ -z "${MOONSHOT_API_KEY:-}" ]] && { echo "ERROR: MOONSHOT_API_KEY not set in ~/.brain-secrets" | tee -a "$LOG"; exit 1; }
    API_URL="https://api.moonshot.cn/v1/chat/completions"
    MODEL="kimi-k2-0905-preview"
    AUTH_HEADER="Authorization: Bearer $MOONSHOT_API_KEY"
    EXTRACT='.choices[0].message.content'
    BODY_FMT="openai"
    ;;
  anthropic)
    [[ -z "${ANTHROPIC_API_KEY:-}" ]] && { echo "ERROR: ANTHROPIC_API_KEY not set in ~/.brain-secrets" | tee -a "$LOG"; exit 1; }
    API_URL="https://api.anthropic.com/v1/messages"
    MODEL="claude-opus-4-7"
    AUTH_HEADER="x-api-key: $ANTHROPIC_API_KEY"
    EXTRACT='.content[0].text'
    BODY_FMT="anthropic"
    ;;
  *)
    echo "ERROR: BRAIN_LLM must be one of llama, deepseek, moonshot, anthropic. Got: $LLM" | tee -a "$LOG"; exit 1 ;;
esac

{
  echo "=== Brain daily brief — $(date) ==="
  echo "Vault: $VAULT"
  echo "Provider: $LLM ($MODEL)"
} > "$LOG"

VAULT_SLICE=$(
  echo "=== CLAUDE.md ==="
  cat "$VAULT/CLAUDE.md" 2>/dev/null || true
  echo
  echo "=== INBOX (last 24h) ==="
  find "$VAULT/inbox" -type f -name '*.md' -mtime -1 -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== NOTES (last 7d) ==="
  find "$VAULT/notes" -type f -name '*.md' -mtime -7 -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== IDEAS (last 7d) ==="
  find "$VAULT/ideas" -type f -name '*.md' -mtime -7 -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== PROJECTS ==="
  find "$VAULT/projects" -type f -name '*.md' -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== RECENT BRIEFS ==="
  find "$VAULT/daily-briefs" -type f -name '*.md' -mtime -3 -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
)

SLICE_SIZE=$(echo "$VAULT_SLICE" | wc -c | xargs)
echo "Vault slice: $SLICE_SIZE chars" >> "$LOG"

# Count REAL captures: files in inbox/notes/ideas with a 'source:' frontmatter line
# that names an external capture pipeline (readwise/whisper/telegram/airr/iOS).
# Seed and meta files won't have these. Threshold of 3 means we have at least
# a handful of genuinely accumulated captures.
REAL_CAPTURE_COUNT=$(find "$VAULT/inbox" "$VAULT/notes" "$VAULT/ideas" -type f -name '*.md' -mtime -7 \
  -exec grep -l -E '^source:[[:space:]]*(readwise|whisper|telegram|airr|ios|webhook)' {} \; 2>/dev/null | wc -l | xargs)
# Also count how many files in inbox/notes/ideas are NOT seed/setup
NON_SEED_COUNT=$(find "$VAULT/inbox" "$VAULT/notes" "$VAULT/ideas" -type f -name '*.md' -mtime -7 \
  ! -name 'seed-*' ! -name '*-second-brain-architecture-source.md' ! -name '*-seed-*' 2>/dev/null | wc -l | xargs)
echo "Real captures (with source:): $REAL_CAPTURE_COUNT" >> "$LOG"
echo "Non-seed files in 7d window: $NON_SEED_COUNT" >> "$LOG"

# Decide engagement vs refusal deterministically (not LLM-judged)
if (( NON_SEED_COUNT < 3 )); then
  VAULT_STATE="THIN"
else
  VAULT_STATE="ENGAGE"
fi
echo "Vault state: $VAULT_STATE" >> "$LOG"

USER_PROMPT="You are running the daily brief over Carlos's Brain vault. Today: $DATE. Vault is below.

VAULT_STATE: $VAULT_STATE
- ENGAGE: produce all four sections with full quality bars.
- THIN: produce ONLY the opening paragraph (refusal) and stop.

Be terse. Carlos reads a lot.

================================================================
## What I'd say if you asked me right now

If VAULT_STATE = THIN, output exactly:

'The vault is too thin for a real brief. There are $NON_SEED_COUNT non-setup files in the last 7 days. The brief becomes useful when actual capture starts flowing — Readwise highlights, voice notes, ideas that came up while you were doing something else. Until then anything I produce is either paraphrase of your seed notes or invention.'

Then STOP. Skip the rest of the sections entirely.

If VAULT_STATE = ENGAGE, write ONE paragraph (3–6 sentences) — your honest read. Not a summary, not a pep talk. What's the state of his thinking? Where is it dense? Where is it sparse? Don't restate his projects back to him; he wrote them. Then proceed to the next sections.

================================================================
## Connections

Up to three real connections. The bar is HIGH.

A connection is real if and only if ALL of these are true:
  (a) The two quotes are from TWO DIFFERENT FILES. Same-file quotes are NEVER a connection — they're the same thought continuing.
  (b) The two files are about DIFFERENT topics on their surface.
  (c) Carlos has not already explicitly written 'A connects to B' anywhere in the vault.

EXAMPLES of fake connections to reject:
  - Two quotes from \`inbox/2026-05-09-seed-cross-project-pattern.md\` — fail (a).
  - Quote about 'capture friction' and quote about 'return path', both from notes about second-brain design — fail (b), both about the same topic.
  - 'Carlos uses Claude Agent SDK' and 'Claude Agent SDK is in his stack defaults' — fail (c), tautology.

SHAPE-EXAMPLE (about a fictional researcher 'Mira' — DO NOT transplant content to Carlos):
  - **Mira's Tuesday note about ferry-route timetables connects to her March essay on logistics-as-narrative — both treat schedules as a kind of story.**
    > 'the 7:42 boat is always 4 minutes late and the regulars build their day around it' — \`inbox/2026-04-22-ferry-watching.md\`
    > 'shipping schedules are how the city tells time' — \`notes/2026-03-08-logistics-as-narrative.md\`

This example shows the SHAPE only. DO NOT use Mira or ferries. Find Carlos's real cross-file connections.

Format each connection as:
- **<one-line claim of why these connect — name something specific>**
  > '<exact quote, ≤25 words>' — \`relative/path/to/file.md\`
  > '<exact quote, ≤25 words>' — \`different/relative/path.md\`

VERIFICATION: before outputting any connection, look at the two file paths. If they are identical, DELETE the connection. Do not output it.

Use vault-relative paths only. Drop the '/Users/carlos/Brain/OBSIDIAN/' prefix.

If you can only honestly produce zero, output exactly: 'No real connections in this slice.' and stop the section.

================================================================
## Pattern

A pattern is real only if Carlos has NOT explicitly named it. Test:
  - Take your candidate pattern phrase.
  - Search the vault for it (case-insensitive).
  - If you find it stated more or less directly, it's not a pattern — it's a quote.
  - If you find every word of it scattered across the vault but never assembled this way, it's a paraphrase, not a pattern.

Example of FAKE pattern (reject): Carlos wrote 'every system I set up should compound.' You then write the pattern is 'Compounding Systems.' That's renaming.

Shape-example of a REAL pattern (about a fictional person, do not transplant): A photographer's vault keeps quoting writers about doors, thresholds, and entryways across unrelated weeks. The unstated pattern: she's working through 'the moment before' as a subject, not the subject itself. She hasn't named it. The vault implies it through what she's drawn to. THAT shape is a pattern. DO NOT copy this content; find Carlos's actual unstated layer if there is one.

If you find a real one: name it as a noun phrase, then ONE paragraph (3 sentences max) explaining what's underneath. Then ONE supporting quote.

If you cannot, output exactly: 'No pattern beyond what Carlos already wrote in plain words.'

================================================================
## Question

ONE question. Banned forms (these are advice-shaped, not real questions):
  - 'How can/will/might X compound/leverage/manifest…?'
  - 'What is the highest-leverage thing…?'
  - 'How do you reconcile X with Y?'
  - Anything ending '…in the next 90 days?' or '…going forward?'

A real question, by contrast:
  - Names a specific tension Carlos hasn't named.
  - Has a YES/NO or A/B-shaped answer (even if the answer is uncertain).
  - Could be answered with 'I don't know yet, let me think for 20 minutes' rather than 'great question, here's a framework.'

EXAMPLES of real questions (about fictional people, do not transplant):
  - 'Mira spent six months claiming she's writing about ferries. Is she actually writing about her father, who took the ferry every day?'
  - 'The photographer's last three shoots were all in airport waiting rooms. Is the project still about doorways, or has it become about leaving?'

These show the shape — naming a tension the person hasn't named. DO NOT copy these. Find Carlos's actual unnamed tension if there is one.

If the only question you have is one of the banned forms, output exactly: 'No question worth asking from this slice.'

================================================================

VAULT BELOW. All file paths in the vault dump are absolute — but in your output, ALWAYS use vault-relative paths (drop the '/Users/carlos/Brain/OBSIDIAN/' prefix) when citing.

$VAULT_SLICE"

SYSTEM_PROMPT="You are an editor for Carlos's second brain. You are not a cheerleader, a coach, or an assistant. Your job is to surface what is real in the vault and refuse to fill space when nothing real is there. Carlos has stated explicitly: 'Sycophancy makes the vault useless.' Output ONLY valid markdown — no preamble, no code fences around the whole thing, no closing pleasantries."

case "$BODY_FMT" in
  anthropic)
    PAYLOAD=$(jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg user "$USER_PROMPT" \
      '{model: $model, max_tokens: 4000, system: $system, messages: [{role: "user", content: $user}]}')
    HEADERS=(-H "$AUTH_HEADER" -H "anthropic-version: 2023-06-01")
    ;;
  llama)
    PAYLOAD=$(jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg user "$USER_PROMPT" \
      '{model: $model, max_completion_tokens: 4000, messages: [{role: "system", content: $system}, {role: "user", content: $user}]}')
    HEADERS=(-H "$AUTH_HEADER")
    ;;
  *)
    PAYLOAD=$(jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg user "$USER_PROMPT" \
      '{model: $model, max_tokens: 4000, messages: [{role: "system", content: $system}, {role: "user", content: $user}]}')
    HEADERS=(-H "$AUTH_HEADER")
    ;;
esac

echo "Calling $LLM…" >> "$LOG"
RESP_FILE="$LOG_DIR/last-response.json"
curl -sS "$API_URL" "${HEADERS[@]}" -H "content-type: application/json" -d "$PAYLOAD" -o "$RESP_FILE"

if jq -e '.error' "$RESP_FILE" >/dev/null 2>&1; then
  echo "ERROR from $LLM API:" >> "$LOG"
  jq '.error' "$RESP_FILE" >> "$LOG"
  exit 1
fi

if ! jq empty "$RESP_FILE" 2>/dev/null; then
  echo "ERROR: response is not valid JSON. See $RESP_FILE" >> "$LOG"
  head -c 500 "$RESP_FILE" >> "$LOG"
  exit 1
fi

CONTENT=$(jq -r "$EXTRACT" "$RESP_FILE")
if [[ -z "$CONTENT" || "$CONTENT" == "null" ]]; then
  echo "ERROR: empty response. Full payload:" >> "$LOG"
  echo "$RESP" >> "$LOG"
  exit 1
fi

cat > "$OUT" <<EOF
---
type: daily-brief
generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
generator: launchd-shell
provider: $LLM
model: $MODEL
---

$CONTENT
EOF

echo "Wrote $OUT" >> "$LOG"
echo "=== Done $(date) ===" >> "$LOG"
