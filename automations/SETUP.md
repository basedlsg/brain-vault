# Setup — the parts only you can do

Everything in this vault is already wired. What's left is the handful of external accounts and apps that need your hands. Plan on **45–60 minutes** end to end. You can do it in two sittings if you split installation from configuration.

> **Operating from mainland China?** Read [`CHINA-AND-LLM-OPTIONS.md`](CHINA-AND-LLM-OPTIONS.md) first — it changes the recommended path. The shortest version: skip Anthropic + N8N + Telegram entirely, use Claude Code's `/schedule` skill for the daily brief and an iOS Shortcut for capture. ~20 minutes total, no API keys.

---

## 0. Prereqs

- macOS (you're on Darwin 25.2)
- Node 22 (already installed via NVM — `nvm use 22`)
- An Anthropic API key with credit on it → https://console.anthropic.com/settings/keys
- A phone with Telegram installed

---

## 1. Open the vault in Obsidian (5 min)

1. Install Obsidian → https://obsidian.md/download
2. Launch Obsidian → "Open folder as vault" → select `/Users/carlos/Brain/`
3. Trust the author (yourself) when prompted. This enables community plugins.
4. Settings → Files & Links → Default location for new notes: **`inbox`**
5. Settings → Files & Links → New link format: **Relative path to file** (so links survive folder moves).

You should now see `CLAUDE.md`, `README.md`, `inbox/`, `notes/`, `ideas/`, `projects/`, etc. in the left sidebar.

---

## 2. Connect Readwise → Obsidian (5 min)

1. Get a Readwise account if you don't have one → https://readwise.io
2. In Obsidian → Settings → Community plugins → Browse → install **"Readwise Official"**
3. Enable it. Click "Connect to Readwise" → log in.
4. **Settings:**
   - Library folder location: `notes/readwise`
   - Sync frequency: `automatic` (Readwise will sync every hour)
5. Click "Sync" once to pull historical highlights. Wait — first sync can take a few minutes.

You're now capturing every Kindle highlight, browser-extension highlight, Twitter bookmark, and Pocket save automatically.

> Nothing for you to tag or summarize. Highlight-and-move-on is the whole interaction model.

---

## 3. Stand up N8N (10 min)

Two options. Pick one.

### Option A — N8N Cloud (easiest)
- Sign up → https://n8n.cloud (free tier is fine to start)
- **Caveat:** the daily brief and weekly synthesis workflows need to read files on your local disk. Cloud N8N can't do that. → Use Option B for those two; Option A is fine for the Telegram capture if you point its file write to a Dropbox/iCloud-synced path instead.

### Option B — Self-hosted N8N (recommended for this vault) ✅
```bash
nvm use 22
npm install -g n8n
n8n start
```
N8N runs at http://localhost:5678. Create your local account on first launch.

For "always on" later, run as a launchd service. For now, `n8n start` in a terminal is fine.

---

## 4. Create the Telegram bot (5 min)

1. Open Telegram → search **@BotFather**
2. `/newbot` → give it a name (e.g. "Carlos Brain") and a username (e.g. `carlos_brain_bot`)
3. BotFather replies with a **bot token**. Copy it.
4. Open a chat with your new bot. Send any message. (This is required so the bot can message you back.)

In N8N → Credentials → New → **Telegram API** → paste the token. Save.

---

## 5. Get the Anthropic API key into N8N (2 min)

The daily brief and weekly synthesis workflows read `ANTHROPIC_API_KEY` from N8N's environment.

If self-hosted (Option B):
```bash
# stop the running n8n
ANTHROPIC_API_KEY=sk-ant-... n8n start
```
Or persist it in your shell profile / a `.env` loaded by your launchd plist.

If cloud, set it under Variables in N8N's settings.

---

## 6. Import the three workflows (5 min)

In N8N → top-right menu → **Import from File** → import each in turn:

1. `automations/n8n/01-telegram-to-vault.json`
2. `automations/n8n/02-daily-brief.json`
3. `automations/n8n/03-weekly-synthesis.json`

For each imported workflow:
- Open it
- For Telegram nodes: click the credential dropdown → select your "Brain Telegram Bot" credential
- The vault path is hard-coded to `/Users/carlos/Brain/` — change it if your vault lives elsewhere
- Click **"Save"** then toggle **"Active"** in the top-right

---

## 7. Smoke-test each workflow (10 min)

### Test Telegram capture
- On your phone, send your bot a message: `test from setup`
- Within ~2 seconds you should get back: `Saved → inbox/<timestamp>-test-from-setup.md`
- Open the vault in Obsidian → confirm the file is in `inbox/`

### Test the daily brief
- In N8N → open "Brain — Daily Brief 06:00" → click **"Execute Workflow"** (manual trigger) — don't wait until 06:00
- Wait ~15s for Claude to respond
- Confirm a new file appeared in `daily-briefs/brief-YYYY-MM-DD.md`
- If empty / error: check the HTTP Request node output for Anthropic API errors (usually missing key or wrong header).

### Test the weekly synthesis
- Same drill — manual execute, then check `weekly-syntheses/`

If all three round-trip cleanly, you're done. The schedules will fire automatically from now on.

---

## 8. Optional: voice notes (Whisper) (10 min)

For dictation on the go: install MacWhisper (https://goodsnooze.gumroad.com/l/macwhisper) — drag-drop an `.m4a` recorded on your phone, get a transcript. Save the transcript into `inbox/`. The Telegram bot also accepts long voice messages — extend the workflow's Code node to detect `voice` payloads and route them through Whisper if you want full automation later.

---

## 9. Optional: Airr for podcasts (5 min)

Install Airr → set up the Readwise export integration in Airr settings → podcast clips will flow into `notes/readwise/` alongside article highlights. Same plumbing, no new workflow needed.

---

## What's already done for you

- ✅ Five-folder structure
- ✅ `CLAUDE.md` populated from your project memory (Life Compiler, Nemo, InnoXera)
- ✅ Project index pages with stack notes and constraints already filled in
- ✅ Templates for every capture type
- ✅ Three N8N workflow JSONs ready to import
- ✅ Two seed notes in `inbox/` and `ideas/` so the daily brief has something to chew on day 1

---

## If something is broken

1. **`Read Vault Slice` node fails** → the vault path in the `executeCommand` node is wrong. Edit it.
2. **Claude returns 401** → missing or wrong `ANTHROPIC_API_KEY` in N8N env.
3. **Claude returns 400 on model** → confirm `claude-opus-4-7` is the correct model ID for your account; otherwise swap to `claude-sonnet-4-6` (cheaper) or whatever's current.
4. **Telegram bot doesn't respond** → make sure you opened a chat with the bot first and sent at least one message before the workflow ran.
5. **Vault is empty so daily brief is hollow** → expected on day 1. Highlight three articles, send the bot one quick capture, wait a day. By morning brief #2 it has material.

---

## Maintenance

- **Every Monday morning:** edit `CLAUDE.md` → update "Current Projects" status, "Stuck on", "Next milestone", and "What I Am Reading and Thinking About". Five minutes. This is the single thing that keeps Claude's context fresh.
- **Quarterly:** archive old daily briefs (`daily-briefs/archive-2026-Q2/`) so the folder doesn't get unwieldy in Obsidian's file tree.
- **Anytime:** if a daily brief is consistently off, the fix is almost always in `CLAUDE.md`, not the prompt.
