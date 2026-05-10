# Archive

Historical material — old journal entries, past essays, voice notes from years ago, defunct project docs. **Not** current thinking.

## How this differs from `/notes` and `/ideas`

- `/inbox`, `/notes`, `/ideas` → things from this week / month. Read by the **daily brief** to find what your brain is working on *right now*.
- `archive/` → things from before this week. Read by the **weekly synthesis** when it reaches back across years to find patterns or contradictions. **Skipped** by the daily brief.

This separation keeps the daily brief sharp while making sure old material is still available when synthesis actually needs it.

## Subfolders

- `journals/` — old journal/diary entries.
- `essays/` — long-form pieces you've already written (drafts, finished essays, project post-mortems).
- `voice-transcripts/` — old voice notes that have already been transcribed.
- `old-projects/` — documentation, design docs, and notes from projects you're no longer working on.

## Filing rules

1. **Always date-stamp the filename** with the original date, not the import date. `2022-03-14-on-saudi-edtech-as-policy.md`, not `2026-05-10-...`.
2. **Always include a frontmatter `original_date` field**:
   ```yaml
   ---
   type: journal
   original_date: 2022-03-14
   imported_at: 2026-05-10
   source: notion-export | gdocs | obsidian | paper-journal
   ---
   ```
3. If you don't know the exact date, approximate at the month level (`2022-03-??`) and put the uncertainty in the frontmatter:
   ```yaml
   original_date: ~2022-03
   date_confidence: month
   ```
4. **Don't reorganize as you import.** Keep the original filing structure. Reorganize only when something is actively useful.

## Triage protocol — first import session

Don't try to import everything at once. Pick **10–20 documents** for the first pass. Aim for high-signal, not completeness:

- The journal entry where you figured out something important.
- The essay you keep referring back to.
- The post-mortem of a project that taught you something.
- The voice note you keep meaning to listen to again.
- The document you would be most upset to lose.

Backfill the rest over weeks, not in one sitting.

## Pruning — when in doubt, leave it

Never delete from `archive/`. If something is truly cringe, mark it deprecated:

```yaml
---
type: journal
original_date: 2019-08-01
deprecated: true
deprecated_reason: "I don't endorse this anymore — kept for historical reference."
---
```

Claude will see the `deprecated: true` flag and skip it in synthesis unless explicitly asked to look back.
