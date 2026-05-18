---
branch: docs/readme-screenshots-clean
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-18
---

## Scope

Follow-up to PR #858. Replaces the three README screenshots with clean,
device-framed exports supplied by the user. Touches `README.md` (one
caption word) and `docs/screenshots/*` (three image files), plus
`project.yml` / `project.pbxproj` (version bump 3.29.3/450 →
3.29.4/451).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### What changed and why

PR #858's three images were crops of the design-bundle renders — taken
inside the device bezel, no device frame, and one carried a status-bar
artifact that had to be cropped away. The user supplied three clean,
device-framed exports of the same three screens (Library / Reading /
Settings) — full iPhone frame, clean `9:41` status bar, no prototype
canvas. This PR swaps those in.

- `docs/screenshots/library.png`  — Library (12 books, Continue reading, grid)
- `docs/screenshots/reader.png`   — reading view (Chapter 1 body text + reader chrome)
- `docs/screenshots/settings.png` — Settings sheet (profile, Cloud & Sync, AI, Reading)
- `README.md` — third caption changed `Display settings` → `Settings`,
  because the new third image is the app Settings sheet, not the reading
  Display sheet.

### Correctness checks

1. **README references unchanged paths** — the `## Screens` table already
   pointed at `docs/screenshots/{library,reader,settings}.png`; replacing
   the files in place is sufficient. Verified the three `<img src>` paths
   still resolve to existing files.
2. **Caption accuracy** — image #3 shows the app-level Settings sheet
   (profile header, Cloud & Sync, AI, Reading), so `Settings` is the
   correct caption; the prior `Display settings` would have been wrong.
3. **Honest framing** — these are design-tool exports, not screenshots of
   the running binary. The section prose says "VReader's v2 visual
   identity" and makes no "live capture" claim, so the wording remains
   accurate. Feature #60 (status VERIFIED) shipped this design.
4. **Image weight** — three PNGs, ~677 KB total; reasonable for a README
   asset folder.
5. **Version bump** — 3.29.4 / build 451 (patch — docs / asset change).
   `xcodegen generate` confirmed.

## Verdict

ship-as-is — documentation + image assets + version bump. No Swift logic,
no code risk. Manual fallback used because there is nothing to send to
Codex.
