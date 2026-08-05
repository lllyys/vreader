---
branch: feat/155-wi-2-manifest-filters
threadId: 019fcf64-9588-7cd2-94db-8ed714efe4aa
rounds: 3
final_verdict: ship-as-is
date: 2026-08-05
---

# Gate 4 — implementation audit, feature #155 WI-2

Manifest intent filters, `ImportActivity` skeleton, translucent theme.
Auditor: Codex (`scripts/run-codex.sh`, rule 53), read-only sandbox — independent of
the implementing session (rule 48 author/auditor separation).

| Round | Thread | Verdict |
| --- | --- | --- |
| 1 | `019fcf4d-2a90-7190-996e-978e7e9c43eb` | follow-up-recommended (1 Medium, 2 Low) |
| 2 | `019fcf59-8cc4-79e2-b821-41c4b69a7658` | follow-up-recommended (1 Low) |
| 3 | `019fcf64-9588-7cd2-94db-8ed714efe4aa` | **ship-as-is** (no findings remain) |

Audit prompts asked specifically about **manifest over-breadth** (with
`application/octet-stream` named as the hazard) and `urisFrom`'s **never-throws** claim
under malformed Parcelable extras, plus the task/theme model, the security of a newly
exported component, test quality, and repo conventions.

## Round 1 — 1 Medium, 2 Low

**M1 — `ImportActivity.kt`: `MAX_BATCH` bounded the RESULT, not the WORK.**
`multiStreamUris` filtered the entire `ArrayList` and `clipUris` traversed every
`ClipData` item before `urisFrom` applied `.take(20)`, so an exported activity could be
made to iterate and allocate for a sender's whole payload while the KDoc claimed the cap
bounded hostile work.
*Fixed.* Both extractors now stop **collecting** at `MAX_BATCH` (early `break` /
bounded `while`); `.take()` is gone from `urisFrom`. The `EXTRA_STREAM` list is now
requested as `Parcelable::class.java` rather than `Uri::class.java`, because
`IntentCompat` has two implementations (unchecked container cast below API 34,
type-checked platform call above) and asking for `Uri` lets the newer one reject a
mixed-type list wholesale; asking for the base type makes API 26–36 behave alike and
keeps per-element `is Uri` filtering local. Iteration is over `List<Any?>` so Kotlin
emits no per-element checked cast.

**L1 — `ImportActivity.kt`: one broken `ClipData` item discarded the whole batch.**
A single outer `runCatching` turned any `getItemAt` failure into `emptyList()` — it
satisfied "never throws" but suppressed legal payloads.
*Fixed.* `clipData`, `itemCount` and each `getItemAt(index)` are guarded independently,
so a malformed entry skips itself and the URIs around it survive. Covered by
`aUriLessClipItemDoesNotDiscardTheValidOnesAroundIt`. A genuinely *throwing*
`ClipData.Item` cannot be constructed without a mocking framework (none is on the
`testImplementation` classpath); round 2 assessed that gap as acceptable.

**L2 — `docs/architecture.md` not updated.**
*Accepted, not fixed in this lane — by design.* `docs/architecture.md` is an
orchestrator-owned shared surface under rule 55; the lane is forbidden to edit it and
instead returns the proposed lines in the HANDOFF's `docs_sync`, which the orchestrator
applies in the **same PR**. Round 2 explicitly confirmed this discharges rule 24
"provided the orchestrator applies the proposed architecture lines in the same PR before
the version bump."

Round 1 also **cleared** the two headline concerns: the four-filter separation is
correct with no unintended cross-product; `application/octet-stream` is deliberate plan
policy (D4) backed by WI-5 runtime resolution, not accidental over-breadth; the
`taskAffinity=""` / `noHistory` / `excludeFromRecents` / translucent-non-NoDisplay
combination is internally consistent for an activity that must stay alive across an
async stream open.

## Round 2 — 1 Low

**L3 — no explicit scan bound for a SPARSE payload.** `MAX_BATCH` bounds a dense
payload, but 100 000 URI-less `ClipData` items would still be walked one by one, and the
KDoc's "bounded by Binder's ~1 MB transaction limit" was hand-waving rather than a real
work bound.
*Fixed.* Added `MAX_SCANNED_ITEMS = 200` (10x `MAX_BATCH`, so a legitimately mixed share
still finds its books while hostile cost stays constant), enforced on **both** loops; the
Binder claim is deleted and the KDoc now states both limits. Covered by
`aSparseListPayloadIsBoundedByTheScanCap`, `aSparseClipDataPayloadIsBoundedByTheScanCap`,
and `aUriJustInsideTheScanCapIsStillFound` (which pins the off-by-one).

Round 2 also confirmed the `Parcelable::class.java` switch introduces no API 26–36
hazard and that the per-item `ClipData` guard advances exactly once per iteration and
cannot loop forever.

## Round 3 — clean

> No findings remain. Both loops inspect indices `0..199`, include the boundary item at
> index 199, and exclude index 200. A dense 20-book share completes before the 200-item
> scan cap. The bounds are consistent, and public visibility matches the existing
> `MAX_BATCH` test-facing contract.

**VERDICT: ship-as-is**

## Auditor-suggested test additions (adopted)

Round 1's notes asked the connected test to reject suffix traps. Added as
`typelessView_doesNotFallForSuffixTraps` (`book.epub.bak`, `book.epub/trailing`, a bare
`epub` segment) — all three **pass on a real device**, so the platform itself confirms
`pathPattern` matches the whole path and filter B is not over-broad there.

## Test gates re-run after every audit-driven code change

```
JVM        RUN-ANDROID-TESTS RESULT: SUCCEEDED
           ImportActivityUriExtractionTest  21 tests, 0 failures, 0 errors
           ImportIntentFilterTest            9 tests, 0 failures, 0 errors
CONNECTED  RUN-ANDROID-TESTS RESULT: SUCCEEDED
           ImportFilterResolutionConnectedTest  17 tests, 0 failures, 0 errors
           (real device PackageManager, emulator-5554 / vreader-test AVD, API 35)
```
