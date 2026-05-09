---
project: Life Compiler
status: active
path: /Users/carlos/SEER-DOTH/life-compiler/
last_synced: 2026-05-09
---

# Life Compiler

Personal AI agent / second-self that compiles raw life inputs (calendar, inbox, journal, modules) into structured action.

## Stack

- Next.js 16, TailwindCSS v4, Framer Motion
- Prisma 6 + SQLite (v7 has breaking config — stay on 6 unless `prisma.config.ts` ready)
- Zustand for client state
- Claude Agent SDK — `query()` returns `AsyncGenerator<SDKMessage>`, must iterate to `SDKResultMessage`
- Zod v4 — uses built-in `toJSONSchema()`, no manual conversion. `instanceof` checks broken.
- shadcn v3.8+ requires Zod v4

## Demo state

- Carlos profile seeded
- 8 module configs
- 5 inbox messages
- API routes fall back to demo data if no profile or agent call fails

## Open questions

_(things to think about — will get filled by daily briefs and weekly syntheses)_

## Linked thinking

_(notes from `/notes/` and `/ideas/` Claude has linked here)_
