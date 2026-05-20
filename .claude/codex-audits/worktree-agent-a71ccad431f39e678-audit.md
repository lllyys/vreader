---
branch: worktree-agent-a71ccad431f39e678
threadId: 019e4407-7fd1-7502-a559-1bed40c25c39
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Audit Log — Bug #235 (GH #983)

Fix: AZW3/MOBI Foliate reader's scroll mode must scroll continuously across
chapter boundaries (TXT analog of bug #180, EPUB analog of bug #165).

## Scope of audit

Codex audited a 4-file diff: `paginator.js` (source-of-truth Foliate-js
paginator), `foliate-bundle.js` (esbuild bundle output), `build-bundle.sh`
(rebuild script), a new Swift Testing suite
`FoliatePaginatorScrollBoundaryTests.swift`, and `project.pbxproj`
(xcodegen regeneration). Added two manifest files for the local
toolchain pin (`package.json`, `package-lock.json`).

## Round 1 findings (4)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| paginator.js:560 | Medium | Boundary detect only fires after 250ms debounce — user feels "jump-after-stop", not continuous fling. | **Fixed.** Moved helper invocation from the 250ms-debounced listener into the IMMEDIATE scroll listener that fires at ~60Hz under a fling. The helper short-circuits on `#locked` so concurrent fires collapse into a single section transition. |
| paginator.js:1101 | Low | `atStart = start <= 2` is looser than `#scrollPrev`'s `start > 0` (=0). Asymmetric vs upstream Foliate epsilons. | **Fixed.** Changed `atStart` to `start <= 0` to match `#scrollPrev`'s threshold exactly. `atEnd` keeps `viewSize - end <= 2` to match `#scrollNext`'s 2px epsilon. Comment updated to explain the documented asymmetry. |
| FoliatePaginatorScrollBoundaryTests.swift:72 | Medium | Source-text grep tests don't prove runtime listener wiring; could keep helper in file and still break edge math. | **Fixed.** Added 8 more tests (now 15 total): direction-specific edge calls (`#turnPage(1)` / `#turnPage(-1)`), scrolled-mode accessor literals (`this.viewSize`, `this.end`, `this.start`), `#adjacentIndex(±1)` in both directions, IMMEDIATE-listener wiring with scan window bounded by the next `.addEventListener(` call, and exact epsilon literals (`viewSize - end <= 2`, `start <= 0`). |
| build-bundle.sh:14 | Low | `npx esbuild` not version-pinned; rebuild could drift across machines. | **Fixed.** First as an advisory pin (round-2 partial); then on round-2's feedback, hardened to a full local toolchain: new `package.json` + `package-lock.json` checked in, `build-bundle.sh` calls `./node_modules/.bin/esbuild` directly and auto-bootstraps via `npm ci`. |

## Round 2 findings (2)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| paginator.js:1087 | Low | Helper's block comment still says "after each scroll settles" — stale after the immediate-listener move. | **Fixed.** Rewrote the block comment to describe immediate-listener semantics (live detection, ~60Hz), the separate role of the debounced listener (relocate/anchor maintenance), the re-entrancy story under a fling (`#locked` set synchronously before first await, `#justAnchored` clears mid-flight via the immediate-listener guard), and the documented epsilon asymmetry. |
| build-bundle.sh:20 | Low | Esbuild "pin" was advisory only — script still warned but ran with whatever `npx` resolved. | **Fixed.** Replaced `npx esbuild` with `./node_modules/.bin/esbuild`, added a local `package.json` + `package-lock.json` for the pin, and added auto-bootstrap via `npm install` (further tightened to `npm ci` in round 3). |

Verified by Codex: round-1 fixes 1–3 fully resolved. Fix 4 partially
resolved (advisory pin). No new races found from the immediate-listener
move. `#locked` set synchronously before first `await` correctly closes
the double-fire window; `#justAnchored` clears mid-flight via the
immediate-listener guard so the post-load landing scroll events do not
re-trigger.

## Round 3 findings (2)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| build-bundle.sh:30 | Low | Bootstrap used `npm install` (can rewrite lockfile), weakening the determinism claim. | **Fixed.** Changed bootstrap to `npm ci --no-audit --no-fund --silent` so the lockfile is enforced, not regenerated. Docs explicitly call out lockfile-bump as a maintainer-action. |
| package.json:1 | Low | New JS toolchain implicitly requires node >=18 (declared by esbuild) but not declared in the manifest. | **Fixed.** Added `"engines": { "node": ">=18" }` to package.json. Added node-version preflight to `build-bundle.sh` — fails early with a clear message if node is <18 or missing. |

Round 3 was the audit-loop cap per `.claude/rules/47-feature-workflow.md`.
Both Round-3 findings were Low and both were fixed before exiting the
loop.

## Final verdict

**Ship-as-is.** All Codex findings across 3 rounds were resolved. Zero
open Critical/High/Medium/Low items. The 15-test Swift suite passes;
the bundle rebuilds byte-stably from source via the pinned esbuild
0.28.0; `npm ci` bootstraps cleanly on a fresh `node_modules` checkout.

## Files changed (final state, before version bump commit)

- `vreader/Services/Foliate/JS/paginator.js` — source of truth: added
  `#maybeCrossSectionBoundary()` (24 LOC including comment) + immediate-
  listener wiring (5 LOC including comment).
- `vreader/Services/Foliate/JS/foliate-bundle.js` — regenerated from
  source via the pinned esbuild.
- `vreader/Services/Foliate/JS/build-bundle.sh` — rewritten to use the
  pinned local esbuild + node-version preflight + `npm ci` bootstrap.
- `vreader/Services/Foliate/JS/package.json` — NEW. Pins
  `devDependencies.esbuild = 0.28.0` + `engines.node >= 18`.
- `vreader/Services/Foliate/JS/package-lock.json` — NEW. Lockfile.
- `vreaderTests/Services/Foliate/FoliatePaginatorScrollBoundaryTests.swift`
  — NEW. 15 tests pinning helper presence, listener wiring,
  direction calls, epsilon literals, and source/bundle parity.
- `vreader.xcodeproj/project.pbxproj` — regenerated by `xcodegen` to
  include the new test file.

## Test gate

```
xcodebuild test \
  -only-testing:vreaderTests/FoliatePaginatorScrollBoundaryTests \
  -destination 'platform=iOS Simulator,id=61149F0E-DC18-4BE2-BB37-52659F1F4F62' \
  -parallel-testing-enabled NO
** TEST SUCCEEDED **
Test run with 15 tests in 1 suite passed.
```
