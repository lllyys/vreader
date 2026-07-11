---
branch: feat/135-wi1-readium-reconstruct
threadId: 019f516e-9d04-7b03-bb8e-6ca9d7e1a2b5
rounds: 2
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #135 WI-1: `ReadiumLocatorReconstructor`

Independent Codex audit (rule 53 `scripts/run-codex.sh`, read-only sandbox) of the
canonical `Locator` -> Readium `Locator` reconstruction seam that lets a persisted
bookmark (canonical-only, no precise Readium JSON) be jumped to after reopen /
backup-restore.

Files audited:
- `android/app/src/main/kotlin/com/vreader/app/reader/ReadiumLocatorReconstructor.kt`
- `android/app/src/test/kotlin/com/vreader/app/reader/ReadiumLocatorReconstructorTest.kt`

## Round 1 — verdict: block-recommended (session `019f516e-9d04-7b03-bb8e-6ca9d7e1a2b5`)

Single finding:

- **High — fingerprint mismatch is neither checked nor testable.** The reconstructor
  received only a `PublicationLocatorSource`; `toReadium` had no current-book identity
  to compare `canonical.fingerprintKey` against. A valid locator belonging to ANOTHER
  book could resolve a coincidentally-matching href in this publication and produce a
  non-null Readium locator (silent jump to wrong content). The plan's WI-1 test
  catalogue explicitly requires the `fingerprint-mismatch -> null` case; it was missing.

Everything else was confirmed correct in round 1: the reconstruction chain is exactly
`Url(href)? -> linkWithHref(Url) -> locatorFromLink(Link) -> copyWithLocations(progression, fragments=cfi?)`
(text added afterward via `.copy(text = ...)`), preserving the base locator's non-null
`MediaType` (no hand-built `Locator.Locations`); malformed/blank/null href, unresolved
link, unlocatable link, and structural invalidity all return null; the reconstructor is
separate from the pure-JVM Readium-free `ReadiumLocatorBridge`; the extracted
`PublicationLocatorSource` seam (mirroring `PublicationTocSource`, because `Publication`
is a `final` unmockable class) makes the logic genuinely unit-testable.

### Fix applied

- Both constructors now take `expectedFingerprintKey: String` (the current book's
  `Book.fingerprintKey`, threaded by the WI-7 caller — same identity-via-constructor
  pattern as `ReadiumTocProvider`).
- `toReadium` returns null FIRST — before ANY publication access — when
  `canonical.fingerprintKey != expectedFingerprintKey`.
- Added `fingerprintMismatch_returnsNull_withoutTouchingPublication` (asserts null AND
  that neither `linkWithHref` nor `locatorFromLink` was invoked) and
  `matchingFingerprint_reconstructs` (the gate is a foreign-locator filter, not a
  blanket rejection).

## Round 2 — verdict: ship-as-is (session `019f5176-8c20-7403-acd3-af9edcb68343`)

The round-1 High finding is resolved: the identity gate rejects a foreign locator
before touching the publication, and the new test proves both the null return and the
no-invocation of the seam. No new Critical/High/Medium findings. The reconstruction
chain, degrade-to-null behavior, bridge separation, and unit-testability are all
confirmed intact.

Robolectric suite `com.vreader.app.reader.ReadiumLocatorReconstructorTest`:
14 tests, 0 failures, 0 errors (`RUN-ANDROID-TESTS RESULT: SUCCEEDED`).
