#!/usr/bin/env node
// Brain Vault — local webhook receiver.
//
// Listens on http://0.0.0.0:7891. Accepts:
//   POST /capture   body: {"text": "...", "source": "ios", "tags": ["ai"]}
//                   or raw text body with content-type: text/plain
//   POST /readwise  body: Readwise webhook payload (https://readwise.io/api_deets)
//   GET  /health    plain "ok"
//
// Auth: Authorization: Bearer <BRAIN_WEBHOOK_TOKEN from ~/.brain-secrets>
//   The /health endpoint is unauthenticated. Everything else requires the token.
//
// Why bind to 0.0.0.0: lets your phone on the same WiFi POST directly without
// going through any cloud. Lock down by leaving BRAIN_WEBHOOK_TOKEN secret.
//
// Logs to ~/Brain/OBSIDIAN/automations/scripts/logs/webhook.log

'use strict';

const http = require('http');
const fs   = require('fs');
const path = require('path');

const VAULT      = '/Users/carlos/Brain/OBSIDIAN';
const PORT       = parseInt(process.env.BRAIN_WEBHOOK_PORT || '7891', 10);
const TOKEN      = process.env.BRAIN_WEBHOOK_TOKEN || '';
const LOG_PATH   = path.join(VAULT, 'automations/scripts/logs/webhook.log');
const INBOX      = path.join(VAULT, 'inbox');

if (!TOKEN) {
  console.error('FATAL: BRAIN_WEBHOOK_TOKEN not set. Add to ~/.brain-secrets and reload.');
  process.exit(1);
}

function log(...args) {
  const line = `[${new Date().toISOString()}] ${args.join(' ')}\n`;
  fs.appendFileSync(LOG_PATH, line);
}

function slugify(s) {
  return (s || 'capture')
    .slice(0, 60)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40) || 'capture';
}

function pad(n) { return String(n).padStart(2, '0'); }

function writeCapture({ text, source, tags }) {
  const now    = new Date();
  const date   = `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}`;
  const time   = `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const iso    = now.toISOString();
  const slug   = slugify(text);
  const fname  = `${date}-${time}-${slug}.md`;
  const dest   = path.join(INBOX, fname);
  const tagBlk = (Array.isArray(tags) && tags.length) ? `tags: [${tags.join(', ')}]\n` : '';
  const body =
`---
type: quick-capture
source: ${source || 'webhook'}
captured_at: ${iso}
processed: false
${tagBlk}---

# Quick capture — ${date} ${pad(now.getHours())}:${pad(now.getMinutes())}

${text}
`;
  fs.writeFileSync(dest, body, 'utf8');
  return { filename: fname, path: dest };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    const MAX = 1024 * 1024 * 4; // 4MB cap
    req.on('data', (c) => {
      total += c.length;
      if (total > MAX) { req.destroy(); reject(new Error('body too large')); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function authOk(req) {
  const h = req.headers['authorization'] || '';
  return h === `Bearer ${TOKEN}`;
}

const server = http.createServer(async (req, res) => {
  const remote = req.socket.remoteAddress;
  log(`${req.method} ${req.url} from ${remote}`);

  // Health check (unauthenticated, useful for testing the server is alive)
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end('ok');
    return;
  }

  // Everything else requires the token
  if (!authOk(req)) {
    res.writeHead(401, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'unauthorized' }));
    log('  → 401 unauthorized');
    return;
  }

  if (req.method === 'POST' && (req.url === '/capture' || req.url === '/')) {
    try {
      const raw = await readBody(req);
      const ct  = (req.headers['content-type'] || '').toLowerCase();
      let payload;
      if (ct.includes('application/json')) {
        payload = JSON.parse(raw || '{}');
      } else {
        payload = { text: raw };
      }
      if (!payload.text || !payload.text.trim()) {
        res.writeHead(400, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ error: 'missing text' }));
        log('  → 400 missing text');
        return;
      }
      const result = writeCapture(payload);
      log(`  → 200 wrote ${result.filename}`);
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, filename: result.filename }));
    } catch (e) {
      log(`  → 500 ${e.message}`);
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: e.message }));
    }
    return;
  }

  // Readwise webhook handler — fires on highlight create/update events.
  // Payload shape: see https://readwise.io/api_deets#webhook
  // We just write a single capture summarizing the highlight.
  if (req.method === 'POST' && req.url === '/readwise') {
    try {
      const raw = await readBody(req);
      const evt = JSON.parse(raw || '{}');
      const high = evt.highlight || evt;
      const text = `> ${high.text || '(no text)'}\n\n— ${high.author || 'unknown'}, ${high.title || 'unknown source'}\n\n${high.url || ''}`;
      const result = writeCapture({
        text,
        source: 'readwise-webhook',
        tags: ['highlight'],
      });
      log(`  → 200 readwise ${result.filename}`);
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, filename: result.filename }));
    } catch (e) {
      log(`  → 500 ${e.message}`);
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: e.message }));
    }
    return;
  }

  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  log(`Brain webhook listening on 0.0.0.0:${PORT}`);
  console.log(`Brain webhook listening on http://0.0.0.0:${PORT}`);
});

process.on('SIGTERM', () => { log('SIGTERM, shutting down'); server.close(() => process.exit(0)); });
process.on('SIGINT',  () => { log('SIGINT, shutting down');  server.close(() => process.exit(0)); });
