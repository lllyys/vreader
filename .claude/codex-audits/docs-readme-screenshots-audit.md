---
branch: docs/readme-screenshots
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-18
---

## Scope

Docs-only change: adds a `## Screens` section to `README.md` and six PNG
assets under `docs/screenshots/`. Touches `README.md`, `docs/screenshots/*`
(new), plus `project.yml` / `project.pbxproj` (version bump 3.27.28/442 →
3.27.29/443).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### What changed and why

- `README.md`: new `## Screens` section inserted after `## About`, before
  `## Features`. Contains a 5-theme reader showcase (Paper / Sepia / Dark /
  OLED / Photo) in an HTML `<table>` and the Library grid as a single image.
- `docs/screenshots/`: six new PNGs — `library.png`, `theme-paper.png`,
  `theme-sepia.png`, `theme-dark.png`, `theme-oled.png`, `theme-photo.png`.
  Total 816 KB.

### Provenance of the images

All six are live iOS Simulator captures (iPhone 17 Pro, iOS 26.x) of the
**shipped** app — not design-prototype renders. Captured via
`xcrun simctl io booted screenshot` against a Debug build of the current
`main` after seeding the `war-and-peace` TXT fixture and driving the reader
theme through the `vreader-debug://theme?mode=<paper|sepia|dark|oled|photo>`
DebugBridge command. Each theme capture was visually verified to show the
correct themed surface, ink, and accent colour. The Library capture shows
the v2 identity (serif "Library" heading, generative navy cover, toolbar).

### Correctness checks

1. **Image paths** — README references `docs/screenshots/<name>.png` with
   relative paths; the six files exist at exactly those paths (verified via
   `ls docs/screenshots/`). GitHub renders relative image paths from repo
   root, so the links resolve on the project page.
2. **HTML-in-Markdown** — the `<table>` of `<img width=...>` is standard
   GitHub-Flavored-Markdown; GitHub renders inline HTML in README files.
   Every `<img>` has an `alt` attribute.
3. **Honest captions** — the section is captioned "Live captures from the
   iOS Simulator … showing VReader's v2 visual identity." No claim is made
   that these are anything other than simulator captures of the shipped UI.
4. **No copyright issue** — the `war-and-peace` fixture is a public-domain
   synthetic excerpt bundled in the repo (`vreader/Resources/DebugFixtures/`);
   the captures contain only the book title / author lines plus app chrome.
5. **Version bump** — 3.27.29 / build 443 (patch — docs / asset addition).
   `xcodegen generate` confirmed; `project.pbxproj` reflects the new values.

### Known limitation (accepted)

The five reader-theme captures show the book's front-matter page (title +
author) rather than a body-text page. The bundled TXT fixture detects its
title block as its own chapter, and the reader opens there; navigating into
a body chapter requires a UI tap that could not be driven in this
environment (computer-use clicks did not reach the Simulator; System Events
accessibility was unavailable; `vreader-debug://open` position-seek is
deferred to feature #50). The captures still fully demonstrate each theme's
surface / ink / accent colour and the complete reader chrome, which is the
purpose of the showcase. Accepted as-is; a future capture pass can replace
them with body-text pages if desired.

The AI-panel screen is not included — it is not reachable via the
DebugBridge and could not be captured without a working UI-tap path.

## Verdict

ship-as-is — documentation + image assets + version bump. No Swift logic,
no code risk. Manual fallback used because there is nothing to send to
Codex.
