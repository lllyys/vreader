---
branch: feat/feature-76-wi5-vertical-verify-harness
threadId: 019e8748-c5d0-71d0-8b2f-7fc492e6dea5
rounds: 2
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Feature #76 WI-5 vertical-verify harness

Independent Codex audit (cc-suite via `scripts/run-codex.sh`, model `gpt-5.5`,
effort `high`, read-only) of the DEBUG verification harness that forces the
Foliate content to `vertical-rl` (no real vertical-rl AZW3 fixture exists), so a
real AZW3 exercises the WI-3 vertical windowed-scroll path on-device. It WORKED:
the real CJK AZW3 rendered vertical-rl columns + windowed-scrolled continuously
both directions, RSS bounded (395–415 MB).

- Round 1 session: `019e8748-c5d0-71d0-8b2f-7fc492e6dea5`
- Round 2 session: `019e874f-40fe-7aa1-9df8-05ff139d5a3f`

## Scope

- `vreader/Views/Reader/FoliateSpikeView.swift` — the `--force-foliate-vertical-rl` DEBUG flag → a document-start, main-frame user script defining `window.__vreaderForceVerticalRL`.
- `vreader/Services/Foliate/JS/paginator.js` — both section `afterLoad` sites inject `writing-mode: vertical-rl` (style + inline) BEFORE `getDirection`, gated on the locked `window.` property.
- `vreader/Services/Foliate/JS/foliate-bundle.js` (rebuilt).
- `vreaderTests/Services/Foliate/FoliateVerticalWindowBundleTests.swift` (harness contract tests).

## Findings

| Round | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | Medium | A scripted book iframe could set `parent.__vreaderForceVerticalRL = true` to force the debug path (the global wasn't locked). | FIXED — Swift now `Object.defineProperty(window,'__vreaderForceVerticalRL',{value:<forceVerticalRL>,writable:false,configurable:false})` in EVERY build (value `#if DEBUG`-derived from the flag, else `false`). |
| 1 | Low | The prepended `$styleBefore` could be beaten by author inline/`!important` writing-mode. | FIXED — both hooks also set inline `documentElement.style.setProperty('writing-mode','vertical-rl','important')` + `body.style.setProperty(...)`. |
| 1 | Low | Weak substring test. | FIXED — asserts ≥2 hook sites in source+bundle + a Swift-source check (defineProperty / writable:false / configurable:false / #if DEBUG / .atDocumentStart / forMainFrameOnly). |
| 2 | Medium | The hooks read `globalThis.__vreaderForceVerticalRL`; `globalThis` is itself writable, so a scripted iframe could poison `parent.globalThis = {...}` and bypass the locked `window` property (auditor verified with a node test). | FIXED — both hooks + the test now read the LOCKED `window.__vreaderForceVerticalRL` (a non-configurable global property a book cannot reassign); the test also asserts NO `globalThis.` read remains. |

## Auditor confirmations

- Timing correct: `View.load` calls `afterLoad?.(doc)` then `getDirection(doc)`,
  so the forced writing-mode is in place before the read; both `#mountSection` +
  `#display` sites hooked → whole windowed surface forced on the same axis.
- The harness meaningfully exercises WI-3: once `getDirection` reads `vertical-rl`,
  `scrollModelFor` selects the horizontal axis + negative sign,
  `#applyScrolledContainerAxis` reorients the container, `#ensureWindow` runs the
  windowed path. (It does not validate a real vertical-authored AZW3's publisher
  CSS, but exercises the vertical windowed-scroll math on a real AZW3 loader.)
- R1 CSS-dominance + R2 globalThis-bypass both resolved.

## Verdict

**ship-as-is.** Release is inert (`window.__vreaderForceVerticalRL` is hard-`false`
+ non-writable/non-configurable; the flag is `#if DEBUG`-only). Build + 13 tests
GREEN; the hardened harness re-verified on-device (real CJK AZW3 renders
vertical-rl). This unblocks WI-5 → Feature #76 `VERIFIED`.
