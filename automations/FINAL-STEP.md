# Where things stand

## Commands you have now

```bash
bw                              # morning routine: sync Readwise, generate brief, open it
bc "any thought"                # quick capture → inbox/
bc https://example.com/article  # URL capture: fetch, extract via trafilatura, summarize via Llama → notes/articles/
bc --tags ai,nemo "..."         # tag the capture
bt                              # triage inbox (read-only suggestions)
bt --apply                      # execute the suggested moves (deletes need --confirm-delete)
brain-capture                   # full name of bc (same thing)
brain-wake                      # full name of bw
brain-triage                    # full name of bt
```

All four are in `~/bin/` which is already on your PATH.

## Live automations

```bash
$ launchctl list | grep brain
<pid>  0  com.carlos.brain.webhook            (always running, http://localhost:7891)
-      0  com.carlos.brain.daily-brief        (06:00 weekdays)
-      0  com.carlos.brain.weekly-synthesis   (Mondays 09:00)
```

The brief and synthesis scripts:
- Trigger Readwise sync first (if Obsidian is running)
- Pull live tasks/tags/properties/orphans from obsidian-cli into the prompt context
- Use a deterministic shell-side gate to decide ENGAGE vs THIN — no LLM judgment about whether to refuse
- Fall back to filesystem-only when Obsidian isn't running

## Capture paths (any of these put data in your vault)

| Source | Command / Path | Status |
|---|---|---|
| Laptop terminal | `bc "thought"` or `bc <url>` | ✅ live |
| LAN webhook | `POST http://192.168.110.137:7891/capture` | ✅ live |
| Phone (text/voice) | iOS Shortcut → webhook | ⏳ build the Shortcut once (see automations/CAPTURE-LAYER.md) |
| Articles, tweets, Kindle, Pocket | Readwise → Obsidian plugin → `notes/readwise/` | ⏳ log into the plugin once |
| Apple Notes (4,682 of them) | Obsidian Importer plugin (modal already opened) | ⏳ click through |

## What got built in the last pass

1. **Journal indexer** (`index-journals.sh`)
   Llama walks each .txt in archive/journals/, extracts themes (with verbatim quotes), in-text dates, people, places, projects, distinctive passages. Output: `archive/journals/_indexed/<stem>-index.md`. Synthesis reads these instead of trying to read 35MB of raw journals.

   Currently running in background. Took ~12 min for the first 2MB file. Total run time ~2 hours for 12 files. The result for `Claude-astro-later.txt` extracted **30+ project ideas** (most forgotten — Astro-Quantum Nexus, ChronOS, Cosmic Compass, Llama 4 Hackathon, etc.) and **50+ places** (Seattle, Beijing, Hangzhou, Stone Mountain, Murcia…). Re-running with `--force` refreshes.

2. **URL capture** in `bc`
   `bc <url>` → trafilatura extracts clean article text → Llama produces "why this is in my vault" + 3-7 verbatim key passages + cross-cuts to your active projects. Tested on Wikipedia, works.

3. **brain-wake** morning routine
   One command at the start of your day: Readwise sync, brief generation, brief opens in Obsidian, fresh inbox surfaced, Monday CLAUDE.md reminder.

4. **brain-triage** for inbox cleanup
   Read-only by default. Suggests where each unprocessed inbox item should live (ideas / project / archive / keep / delete). `--apply` executes; `--confirm-delete` is required to actually delete.

5. **Vault Pulse dashboard**
   Top-level `Vault Pulse.md` — Dataview queries that render live in Obsidian: captures-by-source, tag cloud, open tasks, inbox-awaiting-triage, orphans, project status. Already opened in your Obsidian window.

## What's still on you (5-10 minutes total)

1. **Click through the Obsidian Importer modal** (or run `obsidian command id=obsidian-importer:open-modal` to re-open). Pick Apple Notes, output folder = `archive/apple-notes`. The plugin uses Apple's native APIs.

2. **Log into Readwise** in Obsidian Settings → Readwise Official → Connect. After that it auto-syncs hourly, and `bw` triggers an extra sync every morning.

3. **Build the iOS Shortcut** for phone capture. Recipe in `automations/CAPTURE-LAYER.md`. Webhook URL: `http://192.168.110.137:7891/capture`. Bearer token in `~/.brain-secrets`.

## Maintenance ritual (5 min/Monday)

`bw` will remind you on Mondays. Edit `CLAUDE.md`:
- Current Projects: status, Stuck on, Next milestone
- "What I Am Reading and Thinking About"

This is the single thing that keeps briefs sharp.

## Quick reference for everything

```bash
# Run brief now
~/Brain/OBSIDIAN/automations/scripts/run-daily-brief.sh

# Run synthesis now
~/Brain/OBSIDIAN/automations/scripts/run-weekly-synthesis.sh

# Re-run journal indexer (with --force to refresh existing indexes)
~/Brain/OBSIDIAN/automations/scripts/index-journals.sh
~/Brain/OBSIDIAN/automations/scripts/index-journals.sh --force

# Triage inbox (read-only)
bt

# Triage and apply
bt --apply

# Apple Notes import: pick a mode
~/Brain/OBSIDIAN/automations/scripts/import-apple-notes.sh --mode=count
~/Brain/OBSIDIAN/automations/scripts/import-apple-notes.sh --mode=plugin
~/Brain/OBSIDIAN/automations/scripts/import-apple-notes.sh --mode=sqlite  # needs Terminal Full Disk Access

# Tail logs
tail -f ~/Brain/OBSIDIAN/automations/scripts/logs/journal-index.log
tail -f ~/Brain/OBSIDIAN/automations/scripts/logs/webhook.log
tail -f ~/Brain/OBSIDIAN/automations/scripts/logs/daily-brief-$(date +%Y-%m-%d).log

# Status of everything
launchctl list | grep brain
ls ~/bin/b*
```

## Switching the LLM provider

`~/.brain-secrets` already has your Llama key. Other providers are wired but inactive. To switch: set `BRAIN_LLM=` to one of `llama|deepseek|moonshot|anthropic` and add the matching key.

## Security

Two secrets in `~/.brain-secrets` (chmod 600):
- `LLAMA_API_KEY` — was pasted in chat earlier; rotate at your discretion
- `BRAIN_WEBHOOK_TOKEN` — auto-generated locally
