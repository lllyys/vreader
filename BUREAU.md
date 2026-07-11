---
description: The trust-gate rules binding every AI session in this repo — consult the canon before deriving, honor each claim's tier on read, and route every durable write through capture → compile → review.
---

# bureau — durable knowledge for this repo

**Consult the canon before you derive; honor each dossier's trust tier on every read; route every
durable write through the gate — never set `canonical` by hand.**

This repository keeps its durable knowledge in a **bureau** workspace (`canon/`): topic
**cabinet** pages (the reviewed canon) plus an append-only **logbook**. `CLAUDE.md` imports this
file, so the gate below binds **every** session here — honor it whenever you read or write
knowledge in this repo.

## Reach for the canon first

- Before deciding something this repo may have already settled (an architecture choice, a
  convention, a prior call), **consult the canon first** — `bureau:query` — instead of re-deriving
  or guessing. The answer may already be recorded, with its trust tier.
- When a session produces something durable (a decision, a constraint, a resolved question),
  **capture it** — `bureau:note` during the session, or `bureau:file-session` to file the whole
  session — before it ends. Capture is cheap; lost context isn't.

## Honor the trust tier on read

Every cabinet page carries a `status:`. When you use one as memory or context, **honor it**:

- `canonical` — a human approved it → treat as **fact**.
- `verified` — auto-checked against the repo, not yet approved → usable, but reconfirm if it is
  load-bearing.
- `proposed` / `stale` / `contested` — **NOT fact** → verify before relying, and state which tier
  you are leaning on.

Never silently treat a non-`canonical` claim as settled. The tier travels with the claim; if you
cite a cabinet fact, cite its tier too. `bureau:query` enforces this for you.

## Respect the write gate

Never write a durable claim straight into the canon, and never set `canonical` yourself — and do
not hand-edit cabinet pages. Memory is gated: **capture** (it lands in the low-authority logbook) →
**compile** (into cabinet pages as `proposed`/`verified`) → **review** (a human promotes to
`canonical`). The logbook is append-only — never rewrite a past entry.

<!-- bureau:crew -->
<!-- /bureau:crew -->
