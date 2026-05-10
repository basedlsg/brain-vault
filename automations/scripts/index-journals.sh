#!/bin/zsh
# Brain Vault — Llama-driven journal indexer.
#
# For each .txt in archive/journals/, ask Llama to extract:
#   - 5-10 key themes (one phrase each, with one supporting quote)
#   - Dates mentioned in the prose (cross-checked against frontmatter)
#   - Key people/places/projects named
#   - 3-5 distinctive passages worth quoting in synthesis
#
# Writes archive/journals/_indexed/<original-stem>-index.md with structured
# YAML frontmatter + markdown so both Llama (synthesis) and Carlos can read.
#
# Each journal is chunked into ~30KB pieces; Llama processes each chunk; we
# aggregate. Skips raw_corpus.txt (it's a research doc, not a journal) and
# any file already indexed (unless --force).

set -euo pipefail

VAULT="/Users/carlos/Brain/OBSIDIAN"
JOURNALS="$VAULT/archive/journals"
INDEX_DIR="$JOURNALS/_indexed"
LOG="$VAULT/automations/scripts/logs/journal-index.log"
mkdir -p "$INDEX_DIR" "$VAULT/automations/scripts/logs"

# Load secrets
[[ -f "$HOME/.brain-secrets" ]] && { set -a; source "$HOME/.brain-secrets"; set +a; }
[[ -z "${LLAMA_API_KEY:-}" ]] && { echo "ERROR: LLAMA_API_KEY not set" >&2; exit 1; }

FORCE=""
[[ "${1:-}" == "--force" ]] && FORCE="yes"

echo "=== Journal indexer — $(date) ===" > "$LOG"
echo "Journals dir: $JOURNALS" >> "$LOG"
echo "Index dir: $INDEX_DIR" >> "$LOG"

CHUNK_SIZE=30000  # bytes per chunk to send to Llama

call_llama() {
  local sys="$1"
  local user="$2"
  local payload
  payload=$(jq -n --arg system "$sys" --arg user "$user" \
    '{model: "Llama-4-Maverick-17B-128E-Instruct-FP8",
      max_completion_tokens: 2000,
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $user}
      ]}')
  local respfile="/tmp/journal-index-resp-$$.json"
  curl -sS https://api.llama.com/v1/chat/completions \
    -H "Authorization: Bearer $LLAMA_API_KEY" \
    -H "content-type: application/json" \
    -d "$payload" -o "$respfile"
  if jq -e '.error' "$respfile" >/dev/null 2>&1; then
    echo "API error:" >&2
    jq '.error' "$respfile" >&2
    rm -f "$respfile"
    return 1
  fi
  jq -r '.completion_message.content.text // empty' "$respfile"
  rm -f "$respfile"
}

process_chunk() {
  local file_basename="$1"
  local chunk_num="$2"
  local total_chunks="$3"
  local chunk_text="$4"

  local sys="You are extracting structured data from a chunk of someone's personal journal. Be precise. Output ONLY valid JSON matching the schema. No preamble, no code fences."
  local user="Source file: $file_basename
Chunk: $chunk_num of $total_chunks

Return JSON with this exact shape:

{
  \"themes\": [{\"phrase\": \"<short noun phrase>\", \"quote\": \"<≤25 word verbatim quote from this chunk>\"}, ...],
  \"dates_in_text\": [\"<YYYY-MM-DD or YYYY-MM if approximate, list only dates Carlos wrote IN the text>\"],
  \"people\": [\"<name as written>\"],
  \"places\": [\"<as written>\"],
  \"projects\": [\"<project, plan, or named idea>\"],
  \"distinctive_passages\": [\"<verbatim quote, 30-80 words, of a passage with unusual emotional or intellectual weight>\"]
}

Rules:
- ALL quotes must appear verbatim in the chunk below. If you cannot find one, return an empty array.
- 'themes' should be 3-7 items. 'distinctive_passages' should be 1-3 items. Quality over quantity.
- Dates: only those Carlos wrote. Don't infer. Don't include the file's mtime.
- People: real names, not pronouns. Spiritual figures (e.g. ADISA) count.

CHUNK CONTENT:

$chunk_text"

  call_llama "$sys" "$user"
}

aggregate_summary() {
  local file_basename="$1"
  local merged_json="$2"  # path to file containing merged chunk JSON outputs

  local sys="You are summarizing structured extractions from a personal journal. Output a single markdown file body. Be terse."
  local user="The file below contains JSON outputs from multiple chunks of journal '$file_basename', concatenated. Produce a final markdown summary with this structure:

# $file_basename — index

## Top themes (consolidated, deduplicated)
- **<theme>** — <one quote, ≤25 words> [chunk N]

## Dates Carlos wrote in this journal
- YYYY-MM-DD: <one-line context if known>
- ...

## People mentioned
<comma-separated, ≤30 names, deduped>

## Places mentioned
<comma-separated, ≤20 places, deduped>

## Projects / named ideas
<comma-separated>

## Distinctive passages
> '<verbatim quote, 30-80 words>' [chunk N]
> '<verbatim quote>' [chunk N]
> ...

Rules:
- Be terse. This is an INDEX, not a summary.
- Dedupe across chunks but keep the strongest quote for each theme.
- Distinctive passages: pick the 3-5 most striking from across all chunks.

CHUNK JSON DUMP:

$(cat "$merged_json")"

  call_llama "$sys" "$user"
}

# Find target files
FILES=()
for f in "$JOURNALS"/*.txt; do
  base=$(basename "$f" .txt)
  # Skip raw_corpus (research doc, not journal)
  [[ "$base" == "raw_corpus" ]] && { echo "  skip: raw_corpus.txt (research doc, not journal)" >> "$LOG"; continue; }
  # Skip duplicate (Malta_27or28 ≡ grr, keep canonical)
  [[ "$base" == "grr" ]] && { echo "  skip: grr.txt (byte-identical to Malta_27or28.txt)" >> "$LOG"; continue; }
  # Skip if already indexed unless --force
  if [[ -f "$INDEX_DIR/$base-index.md" && -z "$FORCE" ]]; then
    echo "  skip: $base (already indexed; use --force to re-run)" >> "$LOG"
    continue
  fi
  FILES+=("$f")
done

echo "Files to index: ${#FILES[@]}" | tee -a "$LOG"

for f in "${FILES[@]}"; do
  base=$(basename "$f" .txt)
  size=$(wc -c < "$f" | xargs)
  echo "" | tee -a "$LOG"
  echo "→ $base ($size bytes)" | tee -a "$LOG"

  total_chunks=$(( (size + CHUNK_SIZE - 1) / CHUNK_SIZE ))
  merged="/tmp/journal-merged-$base-$$.json"
  > "$merged"
  echo "[" >> "$merged"

  chunk_num=0
  byte_pos=0
  while (( byte_pos < size )); do
    chunk_num=$(( chunk_num + 1 ))
    chunk_text=$(dd if="$f" bs=1 skip=$byte_pos count=$CHUNK_SIZE 2>/dev/null)
    byte_pos=$(( byte_pos + CHUNK_SIZE ))

    echo "  chunk $chunk_num/$total_chunks..." | tee -a "$LOG"
    chunk_json=$(process_chunk "$base.txt" "$chunk_num" "$total_chunks" "$chunk_text" 2>>"$LOG" || echo "")

    if [[ -z "$chunk_json" ]]; then
      echo "    chunk $chunk_num: empty/failed response" | tee -a "$LOG"
      continue
    fi

    # Strip code fences if Llama added them despite instructions
    chunk_json=$(echo "$chunk_json" | sed -E 's/^```(json)?//; s/```$//')

    # Validate it's parseable JSON; if not, skip
    if ! echo "$chunk_json" | jq empty >/dev/null 2>&1; then
      echo "    chunk $chunk_num: unparseable JSON, skipping" | tee -a "$LOG"
      continue
    fi

    # Append, with chunk number annotation
    echo "$chunk_json" | jq --arg n "$chunk_num" '. + {chunk: ($n | tonumber)}' >> "$merged"
    echo "," >> "$merged"
  done

  # Close JSON array (remove trailing comma)
  sed -i '' '$s/,$//' "$merged"
  echo "]" >> "$merged"

  # Validate merged
  if ! jq empty "$merged" >/dev/null 2>&1; then
    echo "  merged JSON invalid, skipping aggregation" | tee -a "$LOG"
    continue
  fi

  # Aggregate
  echo "  aggregating..." | tee -a "$LOG"
  summary=$(aggregate_summary "$base.txt" "$merged" 2>>"$LOG" || echo "")

  if [[ -z "$summary" ]]; then
    echo "  aggregation failed" | tee -a "$LOG"
    rm -f "$merged"
    continue
  fi

  out="$INDEX_DIR/$base-index.md"
  cat > "$out" <<EOF
---
type: journal-index
source_file: archive/journals/$base.txt
indexed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
indexer: llama-4-maverick
chunks: $total_chunks
source_size_bytes: $size
---

$summary

---

_Generated by automations/scripts/index-journals.sh. Re-run with --force to refresh._
EOF
  echo "  ✓ wrote $out" | tee -a "$LOG"
  rm -f "$merged"
done

echo "" | tee -a "$LOG"
echo "✓ Indexer complete." | tee -a "$LOG"
ls "$INDEX_DIR"/*.md 2>/dev/null | wc -l | xargs -I {} echo "  Indexed files: {}" | tee -a "$LOG"
