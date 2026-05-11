#!/bin/bash
# brain-analyze — comprehensive cross-source synthesis of the entire vault.
# Reads from every capture source and asks Llama for one document that
# synthesizes across all of them. Saved to vault root as
# "Vault Analysis - YYYY-MM-DD.md" so it shows at the top of Obsidian.

set -uo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

VAULT="/Users/carlos/Brain/OBSIDIAN"
LOG="$VAULT/automations/scripts/logs/brain-analyze.log"
mkdir -p "$VAULT/automations/scripts/logs"
DATE=$(date +%Y-%m-%d)
OUT="$VAULT/Vault Analysis - $DATE.md"

[[ -f "$HOME/.brain-secrets" ]] && { set -a; source "$HOME/.brain-secrets"; set +a; }
[[ -z "${LLAMA_API_KEY:-}" ]] && { echo "ERROR: LLAMA_API_KEY missing" >&2; exit 1; }

{
  echo "=== brain-analyze — $(date) ==="
} > "$LOG"

CURRENT=$(cat "$VAULT/CLAUDE.md" 2>/dev/null)

JOURNAL_CORPUS=""
if [[ -f "$VAULT/weekly-syntheses/corpus-synthesis-$DATE.md" ]]; then
  JOURNAL_CORPUS=$(cat "$VAULT/weekly-syntheses/corpus-synthesis-$DATE.md")
else
  for f in "$VAULT/archive/journals/_indexed/"*-index.md; do
    [[ -f "$f" ]] || continue
    JOURNAL_CORPUS+="=== $(basename "$f") ===
$(cat "$f")

"
  done
fi

PAGES_SLICE=$(
  total=$(ls "$VAULT/archive/pages/"*.md 2>/dev/null | wc -l | xargs)
  if (( total > 0 )); then
    echo "Pages diary corpus: $total files. Showing 10 most recent. Full set listed at end."
    echo
    recent=$(ls -t "$VAULT/archive/pages/"*.md 2>/dev/null | head -10)
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      echo "--- $f ---"
      head -c 6000 "$f"
      echo
    done <<< "$recent"
    echo
    echo "Full Pages inventory:"
    ls -1 "$VAULT/archive/pages/" 2>/dev/null
  fi
)

APPLE_SLICE=$(
  total=$(find "$VAULT/archive/apple-notes" -type f -name '*.md' 2>/dev/null | wc -l | xargs)
  echo "Apple Notes corpus: $total files."
  echo
  echo "Year distribution (from filename original-date prefix):"
  ls "$VAULT/archive/apple-notes/" 2>/dev/null | awk -F'-' '/^[0-9]/ {print $1}' | sort | uniq -c | sort -k2
  echo
  echo "Most recent 15 by original-date:"
  recent=$(find "$VAULT/archive/apple-notes" -type f -name '*.md' 2>/dev/null | sort | tail -15)
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    echo "--- $f ---"
    head -c 3000 "$f"
    echo
  done <<< "$recent"
)

BROWSER_SLICE=""
if [[ -f "$VAULT/archive/browser-history/$DATE.md" ]]; then
  BROWSER_SLICE=$(awk '/^## By domain/,/^## All visits/' "$VAULT/archive/browser-history/$DATE.md" | head -40)
fi

SLICE_SIZE=$(( ${#CURRENT} + ${#JOURNAL_CORPUS} + ${#PAGES_SLICE} + ${#APPLE_SLICE} + ${#BROWSER_SLICE} ))
echo "Slice sizes: claude.md=${#CURRENT} journal=${#JOURNAL_CORPUS} pages=${#PAGES_SLICE} apple=${#APPLE_SLICE} browser=${#BROWSER_SLICE}; total=$SLICE_SIZE" | tee -a "$LOG"

USER_PROMPT="You are doing a comprehensive analysis of Carlos's vault across five sources:
  1. CLAUDE.md — current self-framing
  2. JOURNAL CORPUS — cross-synthesis of 12 indexed journals 2019→2026
  3. PAGES DIARIES — 22 .pages files from iCloud Pages including 3 ADISA diaries
  4. APPLE NOTES — 4,681 notes spanning 2019-09 → 2026-05
  5. BROWSER HISTORY TODAY — top domains

Output a SINGLE markdown document with this exact structure. Be substantive. Carlos will spend 15 min reading this.

# Vault Analysis — $DATE

## Opening: what does the vault know about you right now
ONE paragraph (5-8 sentences). Honest read across all five sources. Not a per-source summary — the through-line. If there's a contradiction between sources, name it. Quote one striking line from any source.

## The thesis Carlos hasn't written
The unstated thesis across all five sources. Must be something Carlos has NOT explicitly stated in CLAUDE.md. Reject pure paraphrase. Support with quotes from at LEAST two different sources.

## Persistent figures and places
Who recurs? Where? Brief, exhaustive:
- **Spiritual / archetypal**:
- **Recurring real people**:
- **Geographic anchors**:

## Ghost projects across the whole corpus
Cross-reference projects named in JOURNAL CORPUS, Pages, Apple Notes. List those that:
- **Still active (in CLAUDE.md)**: with evidence trail
- **Referenced in 2+ sources but NOT in CLAUDE.md** (dormant): exhaustive
- **One-shot appearances**: organized by source

This is the highest-value section.

## Contradictions and tensions
Self-framing vs. lived evidence. Stated goals vs. recurring obsessions. Today's browser activity vs. stated priorities. Quote both sides. If nothing real, write 'No real contradictions today' and move on.

## What today's activity says
Look at the browser-history domains for today. What is Carlos actually doing today? Match against stated priorities. Aligned or doing something else?

## The one question worth sitting with
ONE specific question Carlos hasn't asked himself in the vault. Yes/no or A/B-shaped. Names a specific tension. Not advice-shaped.

## What's missing from the vault
What KIND of material would dramatically improve the next analysis but isn't here yet? Be specific — not 'more notes' but the actual gap (e.g. 'no record of conversations with collaborators', 'no notes on what didn't work', 'no financial reality check'). ONE or TWO things named.

Hard rules:
- Quote verbatim. Cite source.
- Vault-relative paths.
- No outer code fences.
- Refusal allowed if a section has nothing real.

INPUTS:

[1] CLAUDE.md
$CURRENT

[2] JOURNAL CORPUS
$JOURNAL_CORPUS

[3] PAGES DIARIES
$PAGES_SLICE

[4] APPLE NOTES
$APPLE_SLICE

[5] BROWSER HISTORY TODAY
$BROWSER_SLICE
"

SYSTEM_PROMPT="You are doing a comprehensive cross-source analysis of Carlos's vault. Strict anti-sycophancy. Quote verbatim. Output only valid markdown — no preamble, no outer code fences."

PAYLOAD=$(jq -n --arg sys "$SYSTEM_PROMPT" --arg user "$USER_PROMPT" \
  '{model:"Llama-4-Maverick-17B-128E-Instruct-FP8",
    max_completion_tokens: 8000,
    messages:[{role:"system",content:$sys},{role:"user",content:$user}]}')

RESPFILE="$VAULT/automations/scripts/logs/brain-analyze-resp.json"
echo "Calling Llama (8K output, ~30-60s)..." | tee -a "$LOG"
curl -sS https://api.llama.com/v1/chat/completions \
  -H "Authorization: Bearer $LLAMA_API_KEY" \
  -H "content-type: application/json" \
  -d "$PAYLOAD" -o "$RESPFILE"

if jq -e '.error' "$RESPFILE" >/dev/null 2>&1; then
  echo "ERROR:" | tee -a "$LOG"
  jq '.error' "$RESPFILE" | tee -a "$LOG"
  exit 1
fi

CONTENT=$(jq -r '.completion_message.content.text // empty' "$RESPFILE")
TOKEN_USAGE=$(jq -r '"prompt=\(.metrics[] | select(.metric=="num_prompt_tokens").value) completion=\(.metrics[] | select(.metric=="num_completion_tokens").value)"' "$RESPFILE" 2>/dev/null)
echo "Token usage: $TOKEN_USAGE" | tee -a "$LOG"

if [[ -z "$CONTENT" ]]; then
  echo "ERROR: empty response" | tee -a "$LOG"
  jq . "$RESPFILE" | head -20 | tee -a "$LOG"
  exit 1
fi

cat > "$OUT" <<EOF
---
type: vault-analysis
generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
generator: brain-analyze
provider: llama
model: Llama-4-Maverick-17B-128E-Instruct-FP8
sources: [CLAUDE.md, journal-corpus-synthesis, pages-diaries, apple-notes, browser-history-today]
input_chars: $SLICE_SIZE
token_usage: "$TOKEN_USAGE"
---

$CONTENT

---

_Generated by \`brain-analyze\`. Inputs: CLAUDE.md, 12 journal indexes (~38KB), 22 Pages diaries (10 most recent sampled), 4681 Apple Notes (15 most recent + year histogram), today's browser-history top domains._
EOF

echo "Wrote $OUT" | tee -a "$LOG"
