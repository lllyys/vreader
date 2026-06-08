---
branch: fix/68-dropcap-continuous-scroll
threadId: run-codex.sh
rounds: 1
final_verdict: ship-as-is
date: 2026-06-08
---

# Codex audit — bug #331 (EPUB drop-cap in continuous-scroll)

Scope: `vreader/Models/ReaderThemeV2+EPUBCSS.swift` (drop-cap CSS selector) +
`vreaderTests/Models/ReaderThemeV2EPUBCSSChapterStartTests.swift` (tests).

## Verdict: ship-as-is — No findings.

Codex confirmed:
- `:is(body, .vreader-chapter-content) > p:first-of-type::first-letter` is safe for
  the iOS 17+ floor — WebKit has long supported `:is()`; no compatibility risk in
  the EPUB `WKWebView`.
- The selector matches exactly the two intended shapes (paged `body > p`,
  continuous `.vreader-chapter-content > p`); the child combinator + `:first-of-type`
  yield at most one drop-cap per parent → no multiple drop-caps per chapter, no
  over-match on nested `<p>`s.
- Specificity/override correct (`:is()` takes the most specific branch; every
  declaration is `!important`).
- No selector-injection/escaping concern — both branches are static literals;
  `accent` derives from internal `UIColor` tokens via `cssColor`, not user input.
- The updated tests retain meaningful coverage (pinned selector + R6 child-combinator
  guard, single `::first-letter`, per-theme accent).

Full output: `/tmp/f68-audit.txt`. No fixes required.
