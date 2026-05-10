#!/bin/zsh
# Brain Vault — weekly synthesis runner.
# Invoked by launchd Monday 09:00. Reads full vault (incl. archive/), calls LLM,
# writes weekly-syntheses/synthesis-YYYY-MM-DD.md.
#
# IMPORTANT: archive/journals/ contains huge raw .txt files. The shell builds
# a synopsis (only INDEX.md + curated archive material), not the full content.

set -euo pipefail
setopt NULL_GLOB 2>/dev/null || true  # so missing previous synthesis doesn't error

VAULT="/Users/carlos/Brain/OBSIDIAN"
LOG_DIR="$VAULT/automations/scripts/logs"
mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
LOG="$LOG_DIR/weekly-synthesis-$DATE.log"
OUT="$VAULT/weekly-syntheses/synthesis-$DATE.md"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Portable timeout (macOS lacks GNU `timeout`; perl is always present).
_timeout() {
  local seconds="$1"; shift
  perl -e '$SIG{ALRM}=sub{exit 124};alarm shift;exec {$ARGV[0]} @ARGV' "$seconds" "$@"
}

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
    [[ -z "${DEEPSEEK_API_KEY:-}" ]] && { echo "ERROR: DEEPSEEK_API_KEY not set" | tee -a "$LOG"; exit 1; }
    API_URL="https://api.deepseek.com/chat/completions"
    MODEL="deepseek-chat"
    AUTH_HEADER="Authorization: Bearer $DEEPSEEK_API_KEY"
    EXTRACT='.choices[0].message.content'
    BODY_FMT="openai"
    ;;
  moonshot|kimi)
    [[ -z "${MOONSHOT_API_KEY:-}" ]] && { echo "ERROR: MOONSHOT_API_KEY not set" | tee -a "$LOG"; exit 1; }
    API_URL="https://api.moonshot.cn/v1/chat/completions"
    MODEL="kimi-k2-0905-preview"
    AUTH_HEADER="Authorization: Bearer $MOONSHOT_API_KEY"
    EXTRACT='.choices[0].message.content'
    BODY_FMT="openai"
    ;;
  anthropic)
    [[ -z "${ANTHROPIC_API_KEY:-}" ]] && { echo "ERROR: ANTHROPIC_API_KEY not set" | tee -a "$LOG"; exit 1; }
    API_URL="https://api.anthropic.com/v1/messages"
    MODEL="claude-opus-4-7"
    AUTH_HEADER="x-api-key: $ANTHROPIC_API_KEY"
    EXTRACT='.content[0].text'
    BODY_FMT="anthropic"
    ;;
esac

{
  echo "=== Brain weekly synthesis — $(date) ==="
  echo "Vault: $VAULT"
  echo "Provider: $LLM ($MODEL)"
} > "$LOG"

# Trigger Readwise sync if Obsidian is running so synthesis sees the latest highlights
OBSIDIAN_CLI="/usr/local/bin/obsidian"
OBSIDIAN_AVAILABLE="no"
if [[ -x "$OBSIDIAN_CLI" ]] && pgrep -q "Obsidian" && _timeout 3 "$OBSIDIAN_CLI" files total >/dev/null 2>&1; then
  OBSIDIAN_AVAILABLE="yes"
  echo "Obsidian-cli: available — triggering Readwise sync first" >> "$LOG"
  _timeout 5 "$OBSIDIAN_CLI" command id=readwise-official:readwise-official-sync >/dev/null 2>&1 || true
  sleep 5
else
  echo "Obsidian-cli: unavailable — using filesystem only" >> "$LOG"
fi

OBSIDIAN_CONTEXT=""
if [[ "$OBSIDIAN_AVAILABLE" == "yes" ]]; then
  OBSIDIAN_CONTEXT=$(
    echo "=== OBSIDIAN-MANAGED CONTEXT (live, from running vault) ==="
    echo
    echo "All open tasks (from Obsidian's task index across the whole vault):"
    _timeout 8 "$OBSIDIAN_CLI" tasks todo verbose 2>/dev/null | head -60 || true
    echo
    echo "Active tags with counts (sorted by usage):"
    _timeout 5 "$OBSIDIAN_CLI" tags counts sort=count 2>/dev/null | head -30 || true
    echo
    echo "Most-used frontmatter properties (signals what kinds of capture are flowing):"
    _timeout 5 "$OBSIDIAN_CLI" properties counts sort=count 2>/dev/null | head -20 || true
    echo
    echo "Orphans in active vault (notes nothing else links to — candidates for triage):"
    _timeout 5 "$OBSIDIAN_CLI" orphans 2>/dev/null | grep -v "^archive/" | head -20 || true
    echo
  )
fi

VAULT_SLICE=$(
  echo "=== CLAUDE.md ==="
  cat "$VAULT/CLAUDE.md" 2>/dev/null || true
  echo
  echo "=== ALL INBOX ==="
  find "$VAULT/inbox" -type f -name '*.md' -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== NOTES (last 14d) ==="
  find "$VAULT/notes" -type f -name '*.md' -mtime -14 -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== ALL IDEAS ==="
  find "$VAULT/ideas" -type f -name '*.md' -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== PROJECTS ==="
  find "$VAULT/projects" -type f -name '*.md' -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== ARCHIVE INDEX ==="
  cat "$VAULT/archive/README.md" 2>/dev/null || true
  cat "$VAULT/archive/journals/INDEX.md" 2>/dev/null || true
  # Read the LLM-extracted journal summaries if they exist (much richer than the
  # human-curated INDEX.md, with extracted themes, dates, people, distinctive passages)
  if [[ -d "$VAULT/archive/journals/_indexed" ]]; then
    echo "=== JOURNAL CORPUS — LLM-extracted indexes (use these as the primary lens into the journals) ==="
    for idx in "$VAULT/archive/journals/_indexed/"*-index.md; do
      [[ -f "$idx" ]] || continue
      echo "--- $idx ---"
      cat "$idx"
    done
  fi
  echo "=== ARCHIVE ESSAYS / OLD-PROJECTS / VOICE-TRANSCRIPTS ==="
  find "$VAULT/archive/essays" "$VAULT/archive/old-projects" "$VAULT/archive/voice-transcripts" -type f \( -name '*.md' -o -name '*.txt' \) -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  # Apple Notes — content of the 10 most-recent by original_date (filename date prefix).
  # We deliberately don't dump all 4681 — that would blow context. Synthesis can grep
  # for specific themes via the inventory below if needed.
  if [[ -d "$VAULT/archive/apple-notes" ]]; then
    APPLE_TOTAL=$(find "$VAULT/archive/apple-notes" -type f -name '*.md' 2>/dev/null | wc -l | xargs)
    echo "=== APPLE NOTES — $APPLE_TOTAL total in corpus ==="
    echo "Showing content of the 10 most recent by original_date:"
    echo
    APPLE_RECENT=$(find "$VAULT/archive/apple-notes" -type f -name '*.md' 2>/dev/null | sort | tail -10)
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      echo "--- $f ---"
      head -c 4000 "$f"
      echo
    done <<< "$APPLE_RECENT"
    echo
    echo "Inventory of 50 next-most-recent (filenames only):"
    find "$VAULT/archive/apple-notes" -type f -name '*.md' 2>/dev/null | sort | tail -60 | head -50
    echo
    echo "(For older notes, grep archive/apple-notes/ by theme. Filenames begin with original-date YYYY-MM-DD.)"
  fi
  echo "=== RECENT BRIEFS ==="
  find "$VAULT/daily-briefs" -type f -name '*.md' -mtime -7 -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null
  echo "=== PREVIOUS SYNTHESIS ==="
  prev_syn=$(find "$VAULT/weekly-syntheses" -type f -name '*.md' -print 2>/dev/null | sort -r | head -1)
  if [[ -n "$prev_syn" ]]; then
    echo "--- $prev_syn ---"
    cat "$prev_syn"
  fi
  echo
  echo "$OBSIDIAN_CONTEXT"
)

SLICE_SIZE=$(echo "$VAULT_SLICE" | wc -c | xargs)
echo "Vault slice: $SLICE_SIZE chars" >> "$LOG"

# Engagement gate. Synthesis ENGAGES when there's enough substance to
# synthesize on, in any of three forms:
#   - 5+ recent non-seed captures in inbox/notes/ideas (active week)
#   - 5+ indexed journals in archive/journals/_indexed/ (mined history)
#   - 100+ apple-notes in archive/apple-notes/ (imported corpus)
NON_SEED_COUNT=$(find "$VAULT/inbox" "$VAULT/notes" "$VAULT/ideas" -type f -name '*.md' -mtime -14 \
  ! -name 'seed-*' ! -name '*-second-brain-architecture-source.md' ! -name '*-seed-*' 2>/dev/null | wc -l | xargs)
INDEXED_JOURNAL_COUNT=$(find "$VAULT/archive/journals/_indexed" -type f -name '*-index.md' 2>/dev/null | wc -l | xargs)
APPLE_NOTE_COUNT=$(find "$VAULT/archive/apple-notes" -type f -name '*.md' 2>/dev/null | wc -l | xargs)
echo "Non-seed files in 14d: $NON_SEED_COUNT" >> "$LOG"
echo "Indexed journals: $INDEXED_JOURNAL_COUNT" >> "$LOG"
echo "Apple notes: $APPLE_NOTE_COUNT" >> "$LOG"
if (( NON_SEED_COUNT >= 5 || INDEXED_JOURNAL_COUNT >= 5 || APPLE_NOTE_COUNT >= 100 )); then
  VAULT_STATE="ENGAGE"
else
  VAULT_STATE="THIN"
fi
echo "Vault state: $VAULT_STATE" >> "$LOG"

USER_PROMPT="You are running the weekly synthesis over Carlos's full Brain vault. Today: $DATE. Vault is below.

VAULT_STATE: $VAULT_STATE
- ENGAGE: produce all four sections with full quality bars.
- THIN: produce ONLY the refusal and stop.

Synthesis differs from the daily brief in three ways:
1. It looks at the FULL vault, including archive/.
2. It builds on the recent daily briefs — DO NOT restate what they already named.
3. It is allowed to deliver a hard verdict ('this idea is wrong', 'this project should die', 'you're avoiding this').

If VAULT_STATE = THIN, output exactly:

'# Weekly synthesis — week of $DATE

The vault is too thin for synthesis. There are $NON_SEED_COUNT non-setup files in the last 14 days. Synthesis needs accumulated input. The synthesis becomes useful once Readwise highlights, voice notes, or daily ideas have been flowing in for a couple weeks. Until then, anything I produce is either paraphrase of your seed notes or invention.'

Stop. Skip every other section.

If VAULT_STATE = ENGAGE, output four sections. Be direct. Carlos has stated explicitly: 'Sycophancy makes the vault useless.' Few-shot examples below are SHAPE-illustrations only — DO NOT copy their content verbatim into your output.

================================================================
## Emerging thesis

ONE noun phrase, then ONE paragraph (3–5 sentences) explaining it.

PARAPHRASE TEST. Take your candidate thesis. Search the vault for any of its key nouns/verbs. If you find them clustered in a single passage, you're paraphrasing, not synthesizing. Examples to reject:
  - Carlos wrote 'structured-output agents with grounded evidence.' You write the thesis is 'Evidence-Grounded Compounding Systems.' REJECTED — same words, different order.
  - Carlos wrote 'every system I set up should compound.' You write the thesis is 'Compound Leverage Through Reusable Systems.' REJECTED — same idea, fancier phrase.

A real thesis is a layer UNDERNEATH the stated framing. Shape-example (a DIFFERENT person, do not transplant to Carlos): A novelist's vault keeps quoting cooking memoirs and architecture books and never mentions plot structure. The unstated thesis: she is shifting from a plot-driven writing model to one where setting carries the story. She has not written this; the vault implies it through what she's reading. THAT is a thesis.

If the closest you can come is a restatement, output exactly:

'No emerging thesis this week — Carlos has already named what he's working on explicitly. The vault is too thin for synthesis to find a layer below his stated framing.'

If you do name a thesis, the TWO supporting quotes MUST be from DIFFERENT files. Same-file quotes don't count as triangulation. Format:
> 'quote, ≤25 words' — \`relative/path-A.md\`
> 'quote, ≤25 words' — \`different/relative/path-B.md\`

VERIFICATION before output: check the two paths. If identical, replace the thesis with the refusal above.

================================================================
## Contradictions

Real contradictions only. The bar:
  - Two passages where one says X and the other says not-X about the SAME object.
  - Different LEVELS of analysis (project pattern vs. system pattern) are NOT contradictions.
  - 'Carlos questioning his own pattern-matching' vs. 'Carlos believing in compounding effects' is NOT a contradiction; those are at different levels.
  - A contradiction in the journals (archive/journals/) counts only if it's against something stated in the active vault.

If you cannot find a real contradiction, write exactly: 'No real contradictions this week.' Do not soften, do not invent, do not hedge. Stop.

If you do find one, format as:
- **<one-line claim of the contradiction>**
  > 'quote A' — \`path.md\`
  > 'quote B (the contradicting passage)' — \`path.md\`
  - Why this matters: <one sentence>

================================================================
## Knowledge gap

ONE specific gap. Specific = naming a person, a kind of source, or an angle by name. Examples of acceptable specificity:
  - 'You haven't read anything by Stewart Brand on long-term thinking, despite the InnoXera framing being a long-bet'
  - 'No primary-source Chinese-language compliance documentation in the vault'
  - 'No customer-side voice — all your Nemo notes are about the system, none about the user'

NOT acceptable:
  - 'You're not engaging with the limitations of structured-output agents' (vague, default LLM critique)
  - 'You should explore alternative frameworks' (advice-shaped)

The acceptable examples above are about Carlos but DO NOT copy them verbatim — they're shape-illustrations. Find a real gap by looking at what's IN the vault and asking what's structurally missing.

If you cannot name a gap with the right kind of specificity drawn from this vault, write exactly: 'No specific gap visible from this week's vault slice.'

================================================================
## One action

ONE concrete thing Carlos could do this week. NOT a question. NOT a research direction. NOT generic productivity advice.

Banned actions (these are LLM defaults, not real recommendations):
  - 'Refactor X to better support Y'
  - 'Document the minimal set of components'
  - 'Identify and abstract the reusable primitives'
  - 'Engage with primary sources on X'
  - 'Consider alternative frameworks'

A real action:
  - Names a SPECIFIC thing in his vault (a project, a person he could email, a section he could write).
  - Could be done in a focused 2-hour block.
  - Has a definite output that wasn't there before.

SHAPE-EXAMPLES (about a fictional 'a researcher named Lin' — DO NOT transplant the content to Carlos):
  - 'Lin should pick the single dataset she keeps quoting — the 2018 fisheries set — and rerun her main correlation against it with the new method. Not write the paper, not survey the lit. Just the rerun. Two hours.'
  - 'Lin has saved three notes mentioning the Greenland thaw paper but hasn't read it. Read it this week. If it doesn't change anything, that's also a finding.'

These show the SHAPE (specific object in the vault, 2-hour block, definite output). DO NOT use Lin or her datasets — find Carlos's real specific objects in the actual vault.

If the only action you can think of is generic, or you'd be inventing a specific that isn't actually in the vault, output: 'No specific action this week. The daily brief named <quote the recent brief's action or question>; you haven't done it yet. Do that.'

================================================================

VAULT BELOW. All file paths in the vault dump are absolute — in your output, ALWAYS use vault-relative paths (drop the '/Users/carlos/Brain/OBSIDIAN/' prefix).

$VAULT_SLICE"

SYSTEM_PROMPT="You are an editor doing a weekly synthesis on Carlos's second brain. You are not a cheerleader, a coach, or a self-help author. Your job is to deliver a hard, honest read of what's actually in the vault — and to refuse to fill space with hedged generalities when there is nothing real. Output ONLY valid markdown."

case "$BODY_FMT" in
  anthropic)
    PAYLOAD=$(jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg user "$USER_PROMPT" \
      '{model: $model, max_tokens: 6000, system: $system, messages: [{role: "user", content: $user}]}')
    HEADERS=(-H "$AUTH_HEADER" -H "anthropic-version: 2023-06-01")
    ;;
  llama)
    PAYLOAD=$(jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg user "$USER_PROMPT" \
      '{model: $model, max_completion_tokens: 6000, messages: [{role: "system", content: $system}, {role: "user", content: $user}]}')
    HEADERS=(-H "$AUTH_HEADER")
    ;;
  *)
    PAYLOAD=$(jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg user "$USER_PROMPT" \
      '{model: $model, max_tokens: 6000, messages: [{role: "system", content: $system}, {role: "user", content: $user}]}')
    HEADERS=(-H "$AUTH_HEADER")
    ;;
esac

echo "Calling $LLM…" >> "$LOG"
RESP_FILE="$LOG_DIR/last-response-synthesis.json"
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
  echo "ERROR: empty response" >> "$LOG"
  cat "$RESP_FILE" >> "$LOG"
  exit 1
fi

cat > "$OUT" <<EOF
---
type: weekly-synthesis
generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
generator: launchd-shell
provider: $LLM
model: $MODEL
---

$CONTENT
EOF

echo "Wrote $OUT" >> "$LOG"
echo "=== Done $(date) ===" >> "$LOG"
