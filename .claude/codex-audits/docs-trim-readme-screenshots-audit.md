---
branch: docs/trim-readme-screenshots
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-18
---

## Scope

Follow-up to PR #856. Trims and re-sources the `## Screens` section of
`README.md`: replaces the six simulator captures (1 Library + 5 theme
readers) with three screens — Library, Reading, Display settings. Touches
`README.md`, `docs/screenshots/*`, plus `project.yml` / `project.pbxproj`
(version bump 3.29.2/449 → 3.29.3/450).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### What changed and why

User feedback on PR #856 asked for: fewer images, fewer theme images, more
on-page text (the simulator reader captures showed only the fixture's
front-matter title page), and the three screens Library / Reading /
Settings.

The simulator route could not produce a reading view with real body text
in this environment — computer-use clicks did not reach the Simulator,
System Events accessibility was unavailable, and `vreader-debug://open`
position-seek is deferred to feature #50. The committed design bundle
already contains hi-fi renders of all three screens with full
representative content, so this PR sources the three images from there.

- `README.md`: `## Screens` section rewritten — single 3-column table
  (Library / Reading / Display settings). The five-theme strip is removed;
  the five theme names are kept in the section's prose instead.
- `docs/screenshots/`: `library.png`, `reader.png`, `settings.png` (the
  three new images). Removed: `theme-{paper,sepia,dark,oled,photo}.png`.

### Provenance of the images

The three images are crops of the committed claude.ai/design hi-fi
prototype renders for VReader's v2 visual identity (feature #60, status
VERIFIED — the design shipped):

- `library.png`  ← crop of `dev-docs/designs/vreader-fidelity-v1/project/screenshots/02-library.png`
- `reader.png`   ← crop of `.../06-reader-hq.png`
- `settings.png` ← crop of `.../03-15-reader-settings.png`

Each was cropped (PIL, box `(350,56,574,514)`) to the device-screen
interior, excluding the prototype canvas chrome and the status-bar
text-bleed artifact that made the raw renders unsuitable. Each cropped
result was visually verified clean before use.

### Correctness checks

1. **Honest captioning** — the section prose says "VReader's v2 visual
   identity"; it does NOT claim "live simulator capture" (the prior PR
   #856 text did — that wording is removed because these are design
   renders, not binary screenshots). Feature #60 shipped this exact
   design, so the renders faithfully represent the running app.
2. **Image paths** — README references `docs/screenshots/{library,reader,settings}.png`;
   all three files exist at those paths. Removed files are no longer
   referenced anywhere in `README.md`.
3. **No stale references** — `grep` for `theme-paper|theme-sepia|theme-dark|theme-oled|theme-photo`
   in `README.md` returns nothing after the edit.
4. **HTML-in-Markdown** — standard GFM `<table>` of `<img>` with `alt`
   attributes; renders on the GitHub project page.
5. **Version bump** — 3.29.3 / build 450 (patch — docs / asset change).
   `xcodegen generate` confirmed.

## Verdict

ship-as-is — documentation + image assets + version bump. No Swift logic,
no code risk. Manual fallback used because there is nothing to send to
Codex.
