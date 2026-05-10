# Capture layer — ingesting your digital life

The article describes four capture paths: Readwise, Airr, Whisper, Telegram. With the webhook now live, the actual stack on this machine is:

| Source | Path into vault | Status |
|---|---|---|
| **Quick text from your phone** | iOS Shortcut → webhook → `inbox/` | webhook live, Shortcut needs your hands (5 min, see below) |
| **Voice notes from your phone** | iOS Shortcut Dictate → webhook → `inbox/` | same Shortcut handles both |
| **Articles, Twitter, Kindle** | Readwise → Obsidian plugin → `notes/readwise/` | needs Readwise plugin install |
| **Podcast clips** | Airr → Readwise → same path as articles | covered by Readwise step |
| **Anything from your laptop terminal** | `brain-capture "thought"` CLI | ✅ live |
| **Apple Notes (one-time pull)** | export script | see below |
| **Browser history (read-only)** | optional, see below | optional |

## What's already live

- **Webhook server** at `http://localhost:7891` (also reachable on LAN at `http://192.168.110.137:7891`). Always running via launchd. Auth: bearer token in `~/.brain-secrets` (`BRAIN_WEBHOOK_TOKEN`).
- **`brain-capture` CLI** at `automations/scripts/brain-capture`. Pipe text in or pass as args.

## The thing left for you to do — iOS Shortcut

This replaces the Telegram bot from the article. Five minutes once.

### Setup

1. On your iPhone, open **Shortcuts**.
2. Tap `+` to create a new shortcut.
3. Add these actions in order (search by name in the action picker):

   1. **Dictate Text** — set Stop Listening: "On Tap". (For voice capture.)
   2. **Ask for Input** — Prompt: `Capture (or leave blank)`. Default Answer: `Dictated Text` (use the variable from step 1). Type: Text.
   3. **Set Variable** — Variable Name: `body`. Value: `Provided Input`.
   4. **Get Contents of URL** — URL: `http://192.168.110.137:7891/capture`
      - Method: `POST`
      - Headers:
        - `Authorization` → `Bearer <paste your BRAIN_WEBHOOK_TOKEN here>`
        - `Content-Type` → `application/json`
      - Request Body: **JSON**
        - `text` → variable `body`
        - `source` → text `ios-shortcut`
   5. **Show Notification** — Title: `Brain capture`. Body: `Saved`. (Optional but helpful.)

4. Name the shortcut **"Capture to Brain"**.
5. Tap the share icon → **"Add to Home Screen"**. Now it's one tap from your home screen.

### Lock screen / Action button shortcut

- iPhone 15+ Action Button: Settings → Action Button → Shortcut → "Capture to Brain". Now you press the side button and dictate.
- Older iPhones: add the shortcut to your Lock Screen widget area.

### When you're not on home Wi-Fi

The webhook listens on LAN only by default — when you're on cellular or another network, the shortcut won't reach it. Options:

- **Tailscale (recommended)** — install Tailscale on your laptop and phone, both join your tailnet, then change the Shortcut URL to your laptop's tailnet hostname (e.g. `http://carlos-macbook.tail-scale.ts.net:7891/capture`). The phone reaches the webhook over the tailnet from anywhere.
- **ngrok** — quick but the URL changes each restart. Fine for testing, awkward for daily use.
- **Skip it** — captures only land when you're on home Wi-Fi. The Shortcut still queues your input; you can re-run when home, OR keep a backup that just notes-app-saves to a "capture queue" file you process manually.

Tailscale takes ~15 minutes once and is the right answer.

## Readwise → Obsidian (5 min, one click)

This pulls articles, tweets, Kindle highlights, Pocket, Instapaper into `notes/readwise/` automatically.

1. Sign up / log in: https://readwise.io
2. In Obsidian: Settings → Community plugins → Browse → search **"Readwise Official"** → Install → Enable
3. Click "Connect to Readwise" inside the plugin settings → log in
4. Plugin settings:
   - Library folder: `notes/readwise`
   - Sync frequency: `Every hour`
5. Click "Sync" once to pull your historical highlights.

If you also use **Airr** (podcast clips), enable the Readwise integration in Airr's settings — clips flow through the same Readwise → Obsidian path.

## Apple Notes one-shot import

You probably have years of Apple Notes worth bringing in. There's a script at `automations/scripts/import-apple-notes.sh` (built next) that exports all your notes via AppleScript and drops them into `archive/apple-notes/`. Run once, then forget it — Apple Notes is best treated as a historical layer, not an ongoing capture path. Use the iOS Shortcut for new captures instead.

## Browser history (optional)

If you want what you read but didn't highlight (a weak signal but sometimes useful), `automations/scripts/import-chrome-history.sh` reads `~/Library/Application Support/Google/Chrome/Default/History` and dumps URLs visited in the last week into `archive/browser-history/YYYY-MM-DD.md`. Run it weekly via launchd if you want; skip it if it feels noisy.

## What I'm explicitly NOT building

- **Email ingest** — too noisy, too much PII, marginal signal. Skip unless you have a specific reason.
- **Slack / iMessage / WhatsApp** — privacy/permission overhead doesn't pay off. The few real insights buried in chat are the ones you'd remember anyway.
- **Screen recording / activity tracking** — surveillance disguised as productivity. Hard pass.

The 80/20 capture set for you specifically is: **iOS Shortcut + Readwise + brain-capture CLI**. Everything else is optional.

## Quick reference

```bash
# From your laptop terminal
brain-capture "a thought"
echo "piped thought" | brain-capture --tags ai,nemo

# From anywhere on your LAN (or via Tailscale from anywhere)
curl -sS -X POST http://192.168.110.137:7891/capture \
  -H "Authorization: Bearer $BRAIN_WEBHOOK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"a thought","source":"manual"}'

# Check webhook health
curl http://localhost:7891/health
# → ok

# Check launchd status
launchctl list | grep brain

# Tail the webhook log
tail -f /Users/carlos/Brain/OBSIDIAN/automations/scripts/logs/webhook.log
```
