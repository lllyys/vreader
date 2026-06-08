---
branch: feat/feature-54-phase-d1-epub-replacement
threadId: run-codex.sh
rounds: 1
final_verdict: follow-up-recommended
date: 2026-06-08
---

# Codex audit — feature #54 Phase D-1 (native-EPUB content-replacement rules)

Scope: `EPUBReplacementJS.swift` (new), `ReadiumReaderCoordinator+Replacement.swift`
(new), the Readium + legacy-stitch wiring, and the `--seed-replacement-rule` flag.

## Clean (confirmed by Codex)
- **CFI-safety**: the JS only mutates text-node `nodeValue` + marker attributes,
  never DOM structure — Readium/legacy locators computed against the original HTML
  still resolve.
- **JS injection safety**: rules are JSON-serialized → quote / `</script>` breakout
  is a non-issue for `evaluateJavaScript`.
- **Readium fetch timing**: `replacementRules` are awaited before the navigator is
  built — no stale-empty-JS race.
- **Engine coverage**: matches `ReaderEngine.routeEPUB` paged-vs-scroll split.

## Findings (2 Medium) — ACCEPTED with rationale (v1 scope)

Both findings are about **live rule changes** (editing rules while a book is open),
which is explicitly **out of v1 scope** (rules apply at document open; a rules edit
takes effect on next open — stated in every touched file's comments).

1. **EPUBReplacementJS.swift — `data-vreader-repl` mark is permanent**, so a second
   injection with a different rule set skips already-processed roots; the
   MutationObserver retains the old compiled rules. → **Accepted.** A *correct*
   live re-apply cannot just reprocess: the text is already mutated
   ("Chapter"→"Sektion"), so re-applying new rules to the mutated text is wrong —
   it would need the ORIGINAL per-node text preserved (a materially larger change).
   v1 applies once per fresh document load; a rules edit is picked up on reopen,
   which loads pristine original text. Deferred as a follow-up (would need
   original-text preservation + a rule-set-hash-versioned mark/observer).

2. **EPUBWebViewBridge — `replacementJS` not propagated after `makeUIView`.**
   → **Addressed**: `updateUIView` now syncs `context.coordinator.replacementJS`
   so the stored JS stays current for any later `didFinish`, matching the Readium
   path's `setReplacementRules` forward. The remaining gap (no live re-apply of the
   already-loaded document) is the same v1 limitation as #1.

Net: the core acceptance criterion ("replacement rules work in native EPUB") is met
and device-verified on the legacy stitch (both chapters replaced, observer covers
appended sections); the Readium path uses the same JS + the proven coordinator
pattern. Live mid-read rule edits are a documented v1 limitation, not a core defect.
Full output: `/tmp/f54-audit.txt`.
