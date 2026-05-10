# Running this from Beijing — and without an Anthropic key

Two real obstacles when running this stack from mainland China without VPN reliance:

1. **Anthropic API is not directly accessible.** Direct calls to `api.anthropic.com` are blocked or unreliable.
2. **Telegram is blocked.** The capture bot won't reach Telegram servers without a VPN.

Below: three paths for the intelligence layer (pick one), plus China-friendly substitutes for the capture layer.

---

## Path A — Use Claude Code itself as the runtime (recommended) ⭐

You already have Claude Code running on this machine. Use it as both the writer of the daily brief and the executor — no separate API keys, no N8N HTTP calls, no Anthropic API.

### How it works

Claude Code's `/schedule` skill creates routines that run on a cron schedule. Each scheduled run is a fresh Claude Code session that can read your vault, think, and write files back. That **is** the daily brief, executed by you (Claude Code), not by an N8N HTTP call.

### Set it up

From any Claude Code session at `/Users/carlos/Brain/`:

```
/schedule
```

When the skill prompts:
- **Title:** `Brain — Daily Brief`
- **Cron:** `0 6 * * 1-5` (06:00 weekdays)
- **Prompt:** _(see `prompts/daily-brief.md` — already written for you)_

Repeat for the weekly synthesis:
- **Title:** `Brain — Weekly Synthesis`
- **Cron:** `0 9 * * 1` (Monday 09:00)
- **Prompt:** _(see `prompts/weekly-synthesis.md`)_

That's the entire intelligence layer. No API keys to procure, no proxy to set up, runs from Beijing without friction.

### Trade-offs

- **Pro:** Free (covered by Claude Code subscription), works in China, deepest reasoning.
- **Con:** Only fires when Claude Code is running. If your laptop is closed at 06:00, the brief slips to next start. For most users that's fine — read it whenever you open your laptop.

---

## Path B — DeepSeek API (if you want true 24/7 N8N automation)

DeepSeek is a Chinese model with an OpenAI-compatible API, accessible from mainland China without VPN, very cheap (~10× cheaper than Claude). Quality is excellent for this kind of synthesis task — not Claude-level for nuance, but well above the threshold needed for surfacing connections.

### Get a key

1. Sign up: https://platform.deepseek.com
2. Top up ¥10 (covers months of daily briefs at this prompt size).
3. Settings → API Keys → create one. Copy.

### Update the N8N workflows

In `automations/n8n/02-daily-brief.json` and `03-weekly-synthesis.json`, the HTTP Request node is the only thing that changes. Replace the existing Anthropic call with this body:

```json
{
  "method": "POST",
  "url": "https://api.deepseek.com/chat/completions",
  "sendHeaders": true,
  "headerParameters": {
    "parameters": [
      { "name": "Authorization", "value": "=Bearer {{ $env.DEEPSEEK_API_KEY }}" },
      { "name": "content-type", "value": "application/json" }
    ]
  },
  "sendBody": true,
  "specifyBody": "json",
  "jsonBody": "={\n  \"model\": \"deepseek-chat\",\n  \"max_tokens\": 4000,\n  \"messages\": [\n    {\"role\": \"system\", \"content\": \"You are reading Carlos's Brain vault. Output ONLY valid markdown — no preamble, no code fences.\"},\n    {\"role\": \"user\", \"content\": \"...same prompt as before...\"}\n  ]\n}"
}
```

And the response shape changes — DeepSeek follows OpenAI's format. In the Code node that formats the brief, change:
```js
const text = (resp.content && resp.content[0] && resp.content[0].text) || '';
```
to:
```js
const text = (resp.choices && resp.choices[0] && resp.choices[0].message && resp.choices[0].message.content) || '';
```

A pre-built DeepSeek variant lives at `automations/n8n/02-daily-brief-deepseek.json`.

### Other China-accessible alternatives

| Provider | Model | API base | Notes |
|---|---|---|---|
| **DeepSeek** | `deepseek-chat`, `deepseek-reasoner` | `https://api.deepseek.com` | Cheapest, fastest, OpenAI-compatible. Default pick. |
| **Moonshot (Kimi)** | `kimi-k2-0905-preview` | `https://api.moonshot.cn/v1` | Long context (1M tokens). Useful if vault gets huge. |
| **Alibaba Qwen** | `qwen3-max`, `qwen-plus` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | Solid quality, stable. |
| **Zhipu GLM** | `glm-4.6` | `https://open.bigmodel.cn/api/paas/v4` | Decent, sometimes nuanced. |

All four are OpenAI-compatible, so swap the `url` and the `model` and they work in the same N8N flow.

---

## Path C — MCP-based proxy (advanced)

If you really want Anthropic-grade reasoning from inside China, the practical route is an MCP server that proxies to Claude via a stable channel (a corporate Bedrock account in AWS China region, or a self-hosted reverse proxy on a VPS outside the firewall). This is operationally heavier than A or B and not worth doing unless you have a specific reason.

---

## Capture layer — substitutes for Telegram

Telegram is blocked in China. Three working alternatives:

### Option 1 — WeCom (企业微信) bot
WeCom (Tencent's enterprise WeChat) supports webhook bots that anyone in your group chat can post to. Replace the N8N Telegram trigger with a Webhook trigger; have WeCom post messages there. Detailed steps: https://developer.work.weixin.qq.com/document/path/91770

### Option 2 — Feishu (Lark) bot
Feishu has the same model — a webhook URL that accepts POSTs from a chat. Better dev tooling than WeCom for non-Chinese citizens. https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/bot-v3/add-custom-bot

### Option 3 — iOS Shortcut → N8N webhook
Skip third-party chat entirely. Build an iOS Shortcut: "Capture to Brain" — accepts text input, POSTs to `https://your-n8n.example.com/webhook/brain-capture`. Pin it to your home screen. One tap, one paste, one send.

This is the cleanest path if you want to avoid the chat platforms entirely. Works anywhere in the world.

---

## My recommendation for you specifically

Given you're (a) in Beijing, (b) running Claude Code locally, (c) don't want to pay for an Anthropic API key separately:

1. **Use Path A** for the intelligence layer (`/schedule` in Claude Code).
2. **Use the iOS Shortcut** for capture instead of Telegram — even if you have a VPN, the Shortcut path is more reliable and faster.
3. **Skip N8N entirely for now** — Path A removes the need.
4. **Keep Readwise** — it works fine in China for the highlight sync (the sync runs through Readwise's own infra, accessible from mainland).

That collapses the setup to: install Obsidian, install Readwise plugin, run two `/schedule` commands in Claude Code, build one iOS Shortcut. ~20 minutes total, no API keys.
