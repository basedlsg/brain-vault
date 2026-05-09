---
project: Brain Vault
status: active
path: /Users/carlos/Brain/
last_synced: 2026-05-09
---

# Brain Vault — meta-project

The vault you are reading is itself a project. Track the system here.

## Architecture

1. **Capture:** Readwise + Airr + Whisper + Telegram bot
2. **Pipeline:** N8N (`/automations/n8n/`)
3. **Vault:** This Obsidian folder
4. **Intelligence:** Claude (via `CLAUDE.md` + scheduled briefs)

## Status checklist

- [x] Folder structure
- [x] `CLAUDE.md`
- [x] Project scaffolds
- [x] Templates
- [x] N8N workflow JSONs
- [ ] Obsidian opened on this folder as a vault
- [ ] Readwise → Obsidian plugin connected
- [ ] Telegram bot created (@BotFather) and N8N flow tested
- [ ] N8N daily brief workflow scheduled and verified
- [ ] N8N weekly synthesis workflow scheduled and verified
- [ ] First end-to-end capture round-trip (phone → Telegram → vault → daily brief mentions it)

## Open questions

- Should `/notes/readwise/` be its own subfolder or flat? _(start flat, refactor if it gets noisy)_
- Where do Whisper transcripts land — `/inbox/` or `/ideas/voice/`? _(start `/inbox/`, Claude moves to `/ideas/voice/` during weekly synthesis)_
- Backup story: vault is git-tracked, but should it also sync to iCloud / Dropbox? _(git is enough for now)_

## Linked thinking

_(self-reference — anything in `/notes/` about second brains, knowledge systems, PKM)_
