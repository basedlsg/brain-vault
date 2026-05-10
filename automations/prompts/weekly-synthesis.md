# Weekly Synthesis — prompt

Use this verbatim as the prompt for the `/schedule` skill (or paste into any other automation).

---

You are running the weekly synthesis for Carlos's Brain vault at `/Users/carlos/Brain/`.

Read these:

1. `CLAUDE.md`.
2. Everything in `inbox/`, `notes/`, `ideas/`, `projects/*/` (the full set this time, not just last 7 days).
3. **Everything in `archive/`** that bears on the recent material — old journals, past essays, defunct project docs. This is the folder that makes weekly synthesis different from the daily brief. Use the `original_date` frontmatter to anchor when each piece is from. Skip files marked `deprecated: true` unless an active thread directly contradicts them.
4. The previous five entries in `daily-briefs/` to see what threads have been forming.
5. The previous synthesis in `weekly-syntheses/` if one exists — so you can build on it rather than restart.

Focus your thinking on the last 7 days but draw from older material when it bears on the recent stuff.

Write to `weekly-syntheses/synthesis-YYYY-MM-DD.md` (today's Monday date). Structure:

```markdown
---
type: weekly-synthesis
generated_at: <ISO timestamp>
generator: claude-code-scheduled
---

# Weekly synthesis — week of YYYY-MM-DD

## Emerging thesis

What idea is Carlos building toward without having stated it explicitly yet? What position is forming in his thinking? Quote the breadcrumbs from the vault that point to it.

## Contradictions

What has Carlos saved recently that contradicts something he saved earlier or stated in CLAUDE.md? Show both sides with filenames. This is where the real thinking happens — don't soften it.

## Knowledge gaps

Based on what he's reading and thinking about, what is he clearly NOT reading that he should be? What perspective is missing? Be specific — name the kind of source, the kind of person, or the angle.

## One action

The single highest-leverage thing Carlos could do or think about this week, drawn from everything in the vault. Not a to-do list. One thing.
```

Hard rules:

- Be direct. Challenge him. Do not summarize what he already knows.
- Never claim something is in the vault without quoting it.
- If the contradictions section has nothing — say so. Don't invent contradictions to fill the section.
- Do not edit any other files. Do not modify `CLAUDE.md`. Do not delete previous syntheses or briefs.

When you are done, your last action should be writing the synthesis file. Nothing else.
