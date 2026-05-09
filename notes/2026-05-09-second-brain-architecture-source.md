---
type: note
source: founding-document
captured_at: 2026-05-09
url: (provided by user, no canonical URL)
tags: [second-brain, knowledge-management, n8n, claude, obsidian]
---

# A second brain that talks back — the source article

The article that seeded this entire vault. Captures the thesis, the four-layer architecture, and the "compound interest" framing.

## Key claims I want to test

1. **Friction kills capture.** If capture takes >10 seconds of manual effort, you'll stop under cognitive load. The fix: automate everything.
2. **No connection layer = dead archive.** The vault must actively surface cross-note links, not wait for retrieval.
3. **No reason to return = dead archive.** The vault must push insights back to the user without being asked.
4. **The compound effect is real but takes ~3 months to show up.** Month 1 feels like a tool. Month 3 the connections start landing. Month 6 it's a record of how thinking evolved.

## Architecture

- **Capture:** Readwise (articles/Twitter/Kindle/Pocket) + Airr (podcasts) + Whisper (voice) + Telegram bot (quick saves).
- **Pipeline:** N8N routes each capture into the right vault folder.
- **Storage:** Obsidian, five-folder structure (`inbox`, `notes`, `ideas`, `projects`, `CLAUDE.md`).
- **Intelligence:** Claude reads the vault daily, generates briefs, runs weekly synthesis.

## Three rituals

- **Daily 06:00 weekday:** auto brief — connections, pattern, question.
- **Monday 09:00:** weekly synthesis — emerging thesis, contradictions, knowledge gaps, one action.
- **Anytime:** quick capture from phone via Telegram.

## What I want from this in 90 days

By 2026-08-09 the vault should have:
- Surfaced at least 3 cross-project connections I hadn't seen.
- Caught at least one contradiction in my own thinking.
- Generated at least one weekly-synthesis "one action" that turned into shipped work.

If none of those show up — kill the system, don't keep tending an empty garden.

## Things to watch for

- **Daily brief decay:** if briefs start sounding generic, the fix is in `CLAUDE.md`'s "what I'm reading and thinking" section, not the prompt.
- **Folder sprawl:** "when in doubt → inbox" is the only rule. If new top-level folders appear, that's a smell.
- **Capture friction creep:** if I find myself manually copy-pasting things instead of using Readwise/Telegram/Whisper, a capture path is broken — fix it.
