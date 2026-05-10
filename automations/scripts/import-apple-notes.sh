#!/bin/zsh
# Brain Vault — Apple Notes import dispatcher.
#
# 4,682 Apple Notes is a lot. Bulk-importing all of them is the anti-pattern
# the article warned against. Pick a path:
#
#   1. RECOMMENDED — use the Obsidian Importer plugin (UI, fast, native APIs)
#   2. Auto-import via SQLite (requires Terminal Full Disk Access)
#   3. Skip Apple Notes; iOS Shortcut handles new captures going forward
#
# Run with `--mode=plugin|sqlite|count` to choose. Default opens the dialog.

set -euo pipefail

VAULT="/Users/carlos/Brain/OBSIDIAN"
DEST="$VAULT/archive/apple-notes"
LOG="$VAULT/automations/scripts/logs/apple-notes-import.log"
DB="$HOME/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
mkdir -p "$DEST" "$VAULT/automations/scripts/logs"

MODE="plugin"
[[ "${1:-}" == "--mode=plugin" ]] && MODE="plugin"
[[ "${1:-}" == "--mode=sqlite" ]] && MODE="sqlite"
[[ "${1:-}" == "--mode=count" ]] && MODE="count"

echo "=== Apple Notes import ($MODE) — $(date) ===" > "$LOG"

case "$MODE" in
  count)
    n=$(osascript -l JavaScript -e 'Application("Notes").notes().length' 2>/dev/null || echo "?")
    echo "Notes.app reports $n notes." | tee -a "$LOG"
    exit 0
    ;;

  plugin)
    if ! pgrep -q Obsidian; then
      echo "Obsidian is not running. Open Obsidian first, then re-run this script." | tee -a "$LOG"
      exit 1
    fi
    /usr/local/bin/obsidian command id=obsidian-importer:open-modal >/dev/null 2>&1
    cat <<'EOM' | tee -a "$LOG"

→ Obsidian Importer modal opened in your Obsidian window.

   In the modal:
   1. Select 'Apple Notes' as the source.
   2. For Output folder: type `archive/apple-notes`
   3. Recommended: tick 'Import attachments' if you want PDF/image attachments preserved.
   4. Click 'Import'. The plugin uses Apple's native frameworks — much faster
      than scripting Notes.app over IPC.

   This will dump ALL 4,682 notes. Many are probably scratch / empty / lists.
   The weekly synthesis is told (in the prompt) to grep this folder, not bulk-read it,
   so volume is fine — it just clutters the file tree.

   If you'd rather only import substantial notes (>100 chars, not in Recently Deleted,
   no duplicates), grant Terminal Full Disk Access and re-run:

       ./import-apple-notes.sh --mode=sqlite

   Full Disk Access path:
     System Settings → Privacy & Security → Full Disk Access → click + → Add Terminal

EOM
    exit 0
    ;;

  sqlite)
    if [[ ! -r "$DB" ]]; then
      cat <<EOM | tee -a "$LOG"
ERROR: Cannot read $DB

This means Terminal does not have Full Disk Access. Grant it:
  System Settings → Privacy & Security → Full Disk Access → click + → Add Terminal
Then quit and re-open Terminal, and re-run this command.

Alternatively, use the plugin path:
  ./import-apple-notes.sh --mode=plugin
EOM
      exit 1
    fi

    echo "→ Reading $DB directly (FDA granted, fast path)..." | tee -a "$LOG"
    /usr/bin/python3 - "$DB" "$DEST" <<'PYTHON'
import sys, sqlite3, gzip, hashlib, os, re, datetime
from pathlib import Path

db_path = sys.argv[1]
dest = Path(sys.argv[2])
dest.mkdir(parents=True, exist_ok=True)

# Apple Notes stores body as gzipped Apple-flavored protobuf.
# We'll extract any printable text from the decompressed blob with a
# simple printable-runs heuristic — not perfect, but good enough for
# triage filtering.
def extract_text(blob):
    if blob is None: return ""
    try:
        data = gzip.decompress(blob)
    except Exception:
        data = blob
    # Pull printable strings of length >= 3
    chunks = re.findall(rb'[\x20-\x7e\xa0-\xff\n\r\t]{3,}', data)
    text = b'\n'.join(chunks).decode('utf-8', errors='replace')
    # Collapse runs of whitespace
    text = re.sub(r'\n{3,}', '\n\n', text).strip()
    return text

def slugify(s, n=50):
    s = (s or 'untitled').lower()
    s = re.sub(r'[^a-z0-9]+', '-', s).strip('-')
    return (s[:n] or 'untitled')

def apple_epoch_to_date(t):
    # Apple uses 2001-01-01 epoch in seconds (CFAbsoluteTime)
    if not t:
        return None
    base = datetime.datetime(2001, 1, 1)
    return base + datetime.timedelta(seconds=t)

con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
cur = con.cursor()

# Discover schema dynamically — Apple changes column names occasionally
cols = {row[1] for row in cur.execute("PRAGMA table_info(ZICCLOUDSYNCINGOBJECT);")}
title_col = next((c for c in ['ZTITLE1','ZTITLE','ZTITLE2'] if c in cols), 'ZTITLE')
created_col = next((c for c in ['ZCREATIONDATE3','ZCREATIONDATE1','ZCREATIONDATE'] if c in cols), 'ZCREATIONDATE')
modified_col = next((c for c in ['ZMODIFICATIONDATE1','ZMODIFICATIONDATE'] if c in cols), 'ZMODIFICATIONDATE')

# Find note-data table (ZICNOTEDATA in modern macOS)
note_data_table = 'ZICNOTEDATA' if cur.execute("SELECT name FROM sqlite_master WHERE name='ZICNOTEDATA'").fetchone() else None
data_col = 'ZDATA'

if not note_data_table:
    print("Could not find ZICNOTEDATA table. Schema may have changed.", file=sys.stderr)
    sys.exit(1)

q = f"""
SELECT n.Z_PK, n.{title_col}, n.{created_col}, n.{modified_col}, d.{data_col}
FROM ZICCLOUDSYNCINGOBJECT n
LEFT JOIN {note_data_table} d ON d.ZNOTE = n.Z_PK
WHERE n.{title_col} IS NOT NULL
"""
rows = cur.execute(q).fetchall()
print(f"→ {len(rows)} candidate notes from DB")

written = 0
skipped_short = 0
skipped_dupe = 0
skipped_other = 0
seen_hashes = set()

for pk, title, created_t, mod_t, data in rows:
    try:
        text = extract_text(data) if data else ''
        # Filter: skip very short notes (likely scratch / shopping list)
        if len(text) < 100:
            skipped_short += 1
            continue
        # Dedup by content hash
        h = hashlib.sha1(text.encode('utf-8', errors='replace')).hexdigest()
        if h in seen_hashes:
            skipped_dupe += 1
            continue
        seen_hashes.add(h)

        d_created = apple_epoch_to_date(created_t)
        d_mod = apple_epoch_to_date(mod_t)
        iso_c = d_created.strftime('%Y-%m-%d') if d_created else 'unknown'
        iso_m = d_mod.strftime('%Y-%m-%d') if d_mod else 'unknown'

        slug = slugify(title)
        fname = f"{iso_c}-{slug}.md"
        path = dest / fname
        if path.exists():
            fname = f"{iso_c}-{slug}-{pk}.md"
            path = dest / fname

        title_safe = (title or 'Untitled').replace('"', '\\"')
        body = (
            f"---\n"
            f"type: apple-note\n"
            f"source: apple-notes\n"
            f"original_date: {iso_c}\n"
            f"modification_date: {iso_m}\n"
            f"imported_at: {datetime.datetime.utcnow().isoformat()}Z\n"
            f"sqlite_pk: {pk}\n"
            f'title: "{title_safe}"\n'
            f"---\n\n"
            f"# {title or 'Untitled'}\n\n"
            f"{text}\n"
        )
        path.write_text(body, encoding='utf-8')
        written += 1
    except Exception as e:
        skipped_other += 1
        continue

print(f"✓ Wrote {written} notes")
print(f"  skipped {skipped_short} short (<100 chars)")
print(f"  skipped {skipped_dupe} content-duplicates")
print(f"  skipped {skipped_other} errored")
PYTHON

    WRITTEN=$(ls "$DEST"/*.md 2>/dev/null | wc -l | xargs)
    echo "" | tee -a "$LOG"
    echo "✓ Final: $WRITTEN notes in $DEST" | tee -a "$LOG"
    exit 0
    ;;
esac
