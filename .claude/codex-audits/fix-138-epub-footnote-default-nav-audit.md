---
branch: fix/138-epub-footnote-default-nav
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Restoration of broken footnote navigation. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Views/Reader/EPUBHighlightJS.swift:187-206` | Removed `preventDefault()` + `stopPropagation()` from the footnote click listener; added explanatory comment. |
| `docs/bugs.md` | New row #138 (FIXED, Medium, GH: #296). |

### Why fix

End-to-end pipeline scanned via grep:
- `epubFootnoteDetected` posted: 1 site (`EPUBWebViewBridgeCoordinator.swift:91`).
- `epubFootnoteDetected` observed: 0 sites.

The notification was added with the comment "Post notification for the container to show a footnote popover" — but no popover observer was ever wired. Meanwhile the JS was blocking the default browser scroll-to-anchor behavior. Net effect for users: tap a footnote → nothing happens.

Removing the preventDefault calls restores standard browser anchor-navigation. The messaging infrastructure (handler add, dispatch, post) stays in place so a future popover can hook in by simply observing `.epubFootnoteDetected`.

### Edge cases checked

- **Non-footnote links**: the listener has an `else` (well, the `try` block succeeds + returns or throws). Non-footnote links are untouched (`a` is captured but no `preventDefault` was called for them).
- **`FootnoteDetector` undefined**: outer guard `if (window.__foliate && window.__foliate.FootnoteDetector)`. If detector missing, listener is a no-op. No regression.
- **Detection throws**: caught and lets link navigate normally. Same as before.
- **External links** (http/https): not in scope; the navigation policy handler in `EPUBWebViewBridgeCoordinator` rejects them at the `decidePolicyFor` stage anyway.
- **Anchor link to non-existent ID**: standard browser behavior (silent no-op or jump to top). Same as before.

### What I deliberately did NOT change

- `handleFootnoteMessage` and `.epubFootnoteDetected` declaration: kept for future popover hook-up. Removing them would be cleaner but invasive.
- The footnoteHandler script-message handler add/remove plumbing: kept (3 files would be churned).
- Tests: no targeted tests for the JS click listener; existing JS tests continue to pass.

### Verdict

**ship-as-is**. 2-line removal + comment clarification. Restores broken UX (default browser nav for footnote refs). Keeps messaging infrastructure for future popover.
