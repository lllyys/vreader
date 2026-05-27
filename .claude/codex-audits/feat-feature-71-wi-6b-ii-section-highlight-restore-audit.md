---
branch: feat/feature-71-wi-6b-ii-section-highlight-restore
threadId: 019e67e9-5b9b-7fb1-8b78-94dc93402f62
rounds: 2
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — Feature #71 WI-6b-ii (section-scoped highlight restore, continuous scroll)

Gate-4 implementation audit of `git diff main`. Author = implementing Claude
session; auditor = Codex MCP (separate process — author/auditor separation
satisfied). 2 rounds, terminal verdict **ship-as-is**. Continuous mode is
flag-gated dark behind `FeatureFlags.epubContinuousScroll`.

## Scope

Per-section highlight restore for stitched continuous-scroll chapters: a
`sectionMaterialized` lifecycle message (appended/prepended sections never fire
`didFinish`) + section-relative XPath re-rooting (`__vreader_createHighlightInSection`,
`resolveNodeFromXPathInSection`), driven from the container's `onSectionMaterialized`
hook. A `.vreader-chapter-content` wrapper gives a node whose child-index space
matches the original `<body>`.

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBContinuousScrollJS (sectionHTML) | **High** | The `.vreader-chapter-content` wrapper nested the body's children one level below `<section>`, but `EPUBChapterCSSScoper` collapses root selectors (`html`/`body`/`:root`) onto the section — so `html > body > img` → `[section] > img` matched nothing under the wrapper (rendering regression, unrelated to highlights). | **FIXED.** Made the wrapper the synthetic `<body>` for BOTH subsystems: `EPUBChapterCSSScoper.scopeOne` now collapses root selectors onto `[section] > .vreader-chapter-content` (new `chapterContentSelector` constant). Non-root selectors stay `[section] <sel>` (descendant — still match through the wrapper). Highlight re-rooting resolves against the same wrapper. Updated 3 root-collapse tests. The scoper is only used in continuous mode, so the wrapper always exists. |
| EPUBHighlightJS:188 | Low | `resolveNodeFromXPathInSection` stripped any first two element segments, not the literal `/html/body` its comment claimed — a corrupted path could re-root to the wrong node. | **FIXED.** Strip regex requires the literal `/html/body` prefix; returns null otherwise. |

Round 1 also confirmed: the `rewriteXPathNS` / `applyHighlightRange` extraction is behavior-preserving for the existing document-rooted restore; no Swift-concurrency or message-escaping bug in the `sectionMaterialized` path.

## Round 2 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBHighlightJS:194 | Low | The tightened strip regex still accepted arbitrary positional predicates (`/html[2]/body[9]`), not just optional `[1]`. | **FIXED.** Regex now allows only absent-or-`[1]` predicates with a `(?=/|$)` segment-boundary lookahead. |

Round 2 verdict (verbatim): "No remaining Critical, High, or Medium issues found in the current `git diff main`. The scoper change looks correct: root selectors now collapse onto the synthetic body wrapper, child/descendant combinators preserve the expected semantics through that wrapper, and non-root selectors remain correctly section-scoped without double-prefixing."

## Verdict

**ship-as-is.** Zero open Critical/High/Medium. Both Low findings fixed. Behavioral
correctness of the re-rooting (highlights land on the right text in stitched sections)
is the subject of Gate-5 CU device verification.
