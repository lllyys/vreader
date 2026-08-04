---
branch: feat/139-wi-6-lazy-contents
threadId: orchestrator-run-2026-08-04
rounds: 2
final_verdict: ship-as-is
date: 2026-08-04
---

# Gate 4 — feature #139 WI-6 (lazy Contents sheet)

## Provenance note

The implementing lane fixed its own round-1 findings and committed them
(`470361c3`), but was interrupted before running a confirming round and before
committing this artifact. Round 2 below was therefore run by the **orchestrator**
via `scripts/run-codex.sh` (Codex gpt-5.5 / high) against the branch diff — which
preserves author/auditor separation, since the orchestrator did not write the
implementation. Round-1 findings are recorded from the lane's own commit message;
round 2 is the independent confirming pass and is what this verdict rests on.

Raw round-2 transcript: `<scratchpad>/wi6-audit-r2.txt`.

## Round 1 (in-lane, Codex)

Findings fixed by the lane in `470361c3` before interruption. Not re-litigated
here — round 2 audited the post-fix tree.

## Round 2 (orchestrator-run, Codex gpt-5.5/high)

Scope: the crash trap, end-to-end laziness, the `key(...)` identity, vacuous
Compose assertions, title normalization, and contract preservation.

**Confirmed sound, no finding:**

- **Crash trap handled.** `heightIn(max = 560.dp)` is on the `LazyColumn` itself,
  after the non-empty guard, and `contentPadding` is the right home for the row
  inset. A scrollable measured with infinite vertical constraints throws; no path
  in this diff composes unbounded.
- **Laziness is genuine, end to end.** Seeding
  `rememberLazyListState(initialFirstVisibleItemIndex = currentTocIndex)` composes
  exactly one window. No path composes the top window plus the intervening rows.
- **Contracts preserved.** No designed visual element, token, testTag, empty state,
  or the no-error-surface behaviour changed. Rule 51 clean — the only visible
  deltas are the intended two (opens at the already-designed highlighted row;
  embedded line breaks removed from titles).

### Findings

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | Medium | The laziness oracle is not vacuous, but it can still pass a **wrong truncated** implementation: a bounded `Column(verticalScroll)` over `entries.subList(start, start + 30)` satisfies every row/read bound and every current-row assertion while making the rest of the TOC unreachable. | **FIXED** — see below |
| 2 | Low | `contentSHA256 + entries.size` is not a full TOC identity: the same bytes imported under a different format are a different book with a different TOC, and could wrongly inherit the previous scroll position. | **FIXED** — see below |

## Fixes applied (orchestrator)

**Finding 1 — reachability, not just bounds.** Added
`everyEntryStaysReachable_scrollingToTheLastRow`: scrolls `toc-list` to
`LARGE_COUNT - 1` and requires that row to exist, while still asserting the
composed-row bound. Cheap bounds cannot distinguish *lazy* from *truncated*;
only end-to-end reachability can, so laziness and reachability are now asserted
together — either alone is satisfiable by a wrong implementation.

**Verified by mutation, not by inspection.** `itemsIndexed(entries)` was
temporarily mutated to `itemsIndexed(entries.take(60))` — the auditor's exact
truncation shape — and the suite went from 13/0 to **13 tests / 5 failures**,
with `everyEntryStaysReachable_scrollingToTheLastRow` among the failures. The
mutation was then reverted and the suite re-run green (13/0). This is the
discipline earlier WIs established: WI-2 shipped a test that passed vacuously,
WI-5's differential oracle initially missed a behavioural mutant, so a new
assertion is not trusted until a mutant proves it can fail.

**Finding 2 — identity.** `tocIdentity` now keys on
`entries[0].canonicalLocator.fingerprintKey` (`format:sha256:byteCount`) rather
than `contentSHA256` alone. Same O(1) cost, strictly stronger: format and byte
count are included, so two same-byte imports under different formats cannot
collide. The reason for not keying on the list itself is unchanged and correct —
`List.equals` is O(n), which would re-walk 1,859 entries per recomposition and
re-introduce the exact cost this WI removes.

## Test evidence

All runs on a booted emulator (`emulator-5554`), one class per run per rule 52:

| Suite | Result |
|---|---|
| `TocContentsLargeTocTest` (new) | **13 tests / 0 failures** |
| `TocContentsSheetTest` (pre-existing, **unmodified**) | **11 tests / 0 failures** |
| `TocContentsLargeTocTest` under the truncation mutant | 13 tests / **5 failures** (expected) |

The unmodified pre-existing suite passing is the contract-preservation proof.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium. Both round-2 findings fixed and,
for the Medium, the fix independently demonstrated to fail against the mutant it
was written to catch.
