# Brain — A Second Brain That Talks Back

This is not a filing cabinet. It is a feedback loop.

Every article, podcast clip, voice note, and quick capture flows in here automatically. Claude reads across everything daily and surfaces the connections you missed. The vault briefs you every morning before you open another app. The system compounds without you doing anything extra.

## The four layers

1. **Capture** — Readwise (articles, Twitter, Kindle, Pocket) + Airr (podcasts) + Whisper (voice) + a Telegram bot (quick saves). Nothing manual. Nothing tagged by hand.
2. **Pipeline** — N8N watches each source and routes new content into the right folder of this vault as a clean markdown file.
3. **Vault** — Five folders (`inbox`, `notes`, `ideas`, `projects`, plus `daily-briefs` / `weekly-syntheses` for Claude's output). Local markdown. The ground truth.
4. **Intelligence** — Claude reads the vault every morning, generates the daily brief, runs the weekly synthesis, and answers questions with full context via `CLAUDE.md`.

## Quick start (the parts only you can do)

The folder structure, `CLAUDE.md`, project scaffolds, automations, and templates are already in place. What needs your hands:

1. **Install Obsidian** and open this folder as a vault → see [`automations/SETUP.md`](automations/SETUP.md).
2. **Connect Readwise** (Obsidian plugin) so highlights flow into `/notes/readwise/`.
3. **Set up N8N** (cloud or self-hosted) and import the three workflow JSONs in `/automations/n8n/`.
4. **Create a Telegram bot** with @BotFather, paste the token into N8N.
5. **Set up the Anthropic API key** in N8N for the daily brief and weekly synthesis workflows.

That is it. Once those five steps are done, this vault runs on its own.

## What lives where

| Folder | What |
|---|---|
| `CLAUDE.md` | Read first every session — who I am, current projects, how to behave. |
| `inbox/` | Every fresh automated capture lands here. |
| `notes/` | Processed articles, highlights, research. |
| `ideas/` | My own thinking. |
| `projects/` | One folder per active project. Cross-references vault. |
| `daily-briefs/` | Auto-generated 06:00 weekday briefs. |
| `weekly-syntheses/` | Monday 15-minute deep syntheses. |
| `templates/` | Markdown templates used by the automations. |
| `automations/` | N8N workflows, setup instructions, scripts. |

## The compounding promise

- **Month 1** — feels like a useful tool. You lose fewer ideas.
- **Month 3** — Claude starts connecting things from week 1 to today. The vault knows things about your thinking that you don't.
- **Month 6** — you have a record of every belief you held and changed. Every question you sat with and the answer that emerged. The AI is reading your mind while you live your life.

Most knowledge never compounds because it sits in isolation. This system makes the connections automatically.
