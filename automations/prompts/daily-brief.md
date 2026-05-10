# Daily Brief — prompt

Use this verbatim as the prompt for the `/schedule` skill (or paste into any other automation).

---

You are running the daily brief for Carlos's Brain vault at `/Users/carlos/Brain/`.

Read these in order:

1. `CLAUDE.md` — orientation and current projects.
2. Everything in `inbox/` modified in the last 24 hours.
3. Everything in `notes/` modified in the last 7 days.
4. Everything in `ideas/` modified in the last 7 days.
5. The most recent file in `daily-briefs/` if one exists — so you don't repeat yesterday's connections.

**Do NOT read `archive/`.** That folder is reserved for the weekly synthesis. The daily brief stays focused on current thinking.

Then write a single markdown file to `daily-briefs/brief-YYYY-MM-DD.md` (use today's date, format `2026-05-09`). Structure:

```markdown
---
type: daily-brief
generated_at: <ISO timestamp>
generator: claude-code-scheduled
---

# Daily brief — YYYY-MM-DD

## Connections

The 3 most interesting connections between recent captures and older notes that Carlos has probably not noticed. Be specific. Quote both passages with their source filenames. If there are not three real connections, give fewer rather than padding.

## Pattern

One pattern across this week's captures. What is Carlos's brain working on even if he hasn't said it explicitly? Be willing to call it small or absent if the data is thin.

## Question

One question worth sitting with today, drawn from the pattern. Not a task. A question.
```

Hard rules:

- Never claim something is in the vault without quoting it. If you can't find a source for a claim, drop the claim.
- Convert relative dates ("Thursday") → absolute (`2026-05-14`).
- Be terse. Carlos reads a lot.
- If the vault is too thin to give a real brief (first few days of use), say so plainly under each heading rather than padding. A two-sentence honest brief beats a five-paragraph hollow one.
- Do not edit any other files. Do not modify `CLAUDE.md`. Do not delete previous briefs.

When you are done, your last action should be writing the brief file. Nothing else.
