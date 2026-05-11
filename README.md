# Brain — A Second Brain That Talks Back

> **Lineage.** This repo is a fork of [NicholasSpisak/second-brain](https://github.com/NicholasSpisak/second-brain), which is itself an implementation of [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) (April 2026 gist). Karpathy's idea: instead of asking the LLM to rediscover knowledge from raw files every session, you let it maintain a structured wiki that compounds over time. Karpathy's own wiki reached ~100 articles / 400K words and outperformed RAG for his Q&A.
>
> This fork diverges substantially. It adds: a full automated capture layer (Apple Notes, Pages, browser history, webhook bookmarklet, Readwise plugin config), launchd-scheduled daily-brief + weekly-synthesis pipelines, Llama-API-driven analysis tools (`brain-analyze`, `brain-corpus-synth`, `brain-triage`, `brain-wake`), and an explicit anti-sycophancy prompt-engineering pattern. The original raw/+wiki/ structure is replaced by inbox/+notes/+ideas/+projects/+archive/ — a five-folder scheme closer to PARA than to the wiki pattern. Credit to Karpathy for the compounding-knowledge idea and to NicholasSpisak for the most-cited reference implementation; everything beyond that is in the commits.

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
