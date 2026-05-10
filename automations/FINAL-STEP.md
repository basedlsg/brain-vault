# What's live, what's not

## ✅ Live and verified end-to-end

| Piece | Status | How to test |
|---|---|---|
| Vault structure | live | open `/Users/carlos/Brain/OBSIDIAN/` in Obsidian |
| Daily brief (06:00 weekdays) | launchd loaded, Llama tested | `automations/scripts/run-daily-brief.sh` |
| Weekly synthesis (Mon 09:00) | launchd loaded, Llama tested | `automations/scripts/run-weekly-synthesis.sh` |
| LLM prompts (anti-sycophancy, refuse-when-thin) | tested, cross-file quote rule enforced | see `automations/examples/` |
| `brain-capture` CLI | live | `brain-capture "any text"` |
| Webhook server (`http://localhost:7891`) | launchd KeepAlive, auth working | `curl http://localhost:7891/health` |
| Apple Notes one-shot import | script ready, awaiting your run | `automations/scripts/import-apple-notes.sh` |
| Journal corpus | imported, indexed, dedup-flagged | `archive/journals/INDEX.md` |

## ⏳ Three things left that only you can do

### 1. Build the iOS Shortcut (5 min, on your phone)

Replaces the Telegram bot. One-tap from your home screen → dictate → lands in `inbox/`.

The exact action sequence is in `automations/CAPTURE-LAYER.md` § "iOS Shortcut". You'll need:

- **Webhook URL:** `http://192.168.110.137:7891/capture` (your laptop's LAN IP — only works on home Wi-Fi unless you set up Tailscale)
- **Bearer token:** in `~/.brain-secrets` under `BRAIN_WEBHOOK_TOKEN`. Run `grep BRAIN_WEBHOOK_TOKEN ~/.brain-secrets` to see it.

### 2. Install Readwise plugin in Obsidian (5 min)

Settings → Community Plugins → Browse → "Readwise Official" → Install → Enable → Connect to Readwise → Library: `notes/readwise`.

This pulls articles, tweets, Kindle, Pocket, Instapaper highlights into the vault automatically.

### 3. Run the Apple Notes one-shot import (1 command)

```bash
/Users/carlos/Brain/OBSIDIAN/automations/scripts/import-apple-notes.sh
```

First run may show a permission prompt — grant Terminal access to Notes.app. Output lands in `archive/apple-notes/` with original creation dates preserved in frontmatter.

## Optional next steps (none urgent)

- **Tailscale** — install on laptop + phone, both join your tailnet, change Shortcut URL to your tailnet hostname. Now the iOS Shortcut works from anywhere, not just home Wi-Fi. ~15 min.
- **Airr** for podcast clips → connects to Readwise → same path as articles.
- **Browser history weekly dump** — `automations/scripts/import-chrome-history.sh` exists if you want it. Skip if it feels noisy.

## How the system handles the early-stage thin vault

Both the daily brief and weekly synthesis check the vault for real captured material (files with a `source:` frontmatter from a real pipeline like readwise/whisper/webhook, dated within the brief's lookback window).

- **Vault state THIN** (< 3 non-setup files in 7 days for daily, < 5 in 14 days for synthesis): the brief refuses with a specific count and explanation. No padding, no fake connections.
- **Vault state ENGAGE**: full output with hard quality bars — cross-file quotes only, no paraphrase passing as pattern, banned LLM-default phrasings, refusal sub-sections when a section has nothing real.

You can see both states demonstrated in `automations/examples/`:
- `example-daily-brief-with-real-material.md` — what an engaged brief looks like
- `example-weekly-synthesis-with-real-material.md` — what an engaged synthesis looks like
- The current real `daily-briefs/brief-*.md` and `weekly-syntheses/synthesis-*.md` show graceful refusal with the actual thin vault.

## Quick reference

```bash
# Test the daily brief / synthesis on demand
/Users/carlos/Brain/OBSIDIAN/automations/scripts/run-daily-brief.sh
/Users/carlos/Brain/OBSIDIAN/automations/scripts/run-weekly-synthesis.sh

# Capture from the laptop terminal
brain-capture "thought goes here"
echo "piped" | brain-capture --tags ai,nemo

# Capture from anywhere on LAN
TOKEN=$(grep BRAIN_WEBHOOK_TOKEN ~/.brain-secrets | cut -d'=' -f2 | tr -d '"')
curl -X POST http://192.168.110.137:7891/capture \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"a thought","source":"manual"}'

# Check what's running
launchctl list | grep brain
# expected:
#   <pid>  0  com.carlos.brain.webhook            (always running)
#   -      0  com.carlos.brain.daily-brief        (fires 06:00 weekdays)
#   -      0  com.carlos.brain.weekly-synthesis   (fires Mon 09:00)

# Tail the webhook log
tail -f /Users/carlos/Brain/OBSIDIAN/automations/scripts/logs/webhook.log
```

## Switching the LLM

The wrapper supports four providers via `~/.brain-secrets`. Currently using **llama** (Llama-4-Maverick-17B). To switch: set `BRAIN_LLM=` and add the matching key.

| Provider | Model | When |
|---|---|---|
| **llama** (default) | Llama-4-Maverick-17B | Free for now via your key |
| deepseek | deepseek-chat | If you ever want a cheaper alt |
| moonshot | kimi-k2 | If you want longer context |
| anthropic | claude-opus-4-7 | If you want Opus-level reasoning |

## Maintenance ritual (5 min/week)

Every Monday morning, edit `CLAUDE.md`:
- Update **Current Projects** status, **Stuck on**, **Next milestone**.
- Update **What I Am Reading and Thinking About**.

This is the single thing that keeps the briefs sharp. Stale CLAUDE.md → generic briefs.

## Security note

Two secrets in `~/.brain-secrets` (chmod 600, owner-read):
- `LLAMA_API_KEY` — was pasted in chat earlier, rotate at your discretion via Llama dashboard.
- `BRAIN_WEBHOOK_TOKEN` — auto-generated locally, never left this machine.

The webhook listens on 0.0.0.0:7891 (LAN-reachable). Without the token, requests get 401. If you don't trust your LAN, switch to Tailscale and change the bind address to `127.0.0.1` in `webhook-server.cjs` line 25.
