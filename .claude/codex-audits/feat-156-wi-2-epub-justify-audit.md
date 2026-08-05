---
branch: feat/156-wi-2-epub-justify
threadId: run-codex-3-rounds-gpt-5.5-high
rounds: 3
final_verdict: follow-up-recommended
---

# Gate 4 — feature #156 WI-2 (EPUB justify + `publisherStyles = false`; fixes bug #367 / GH #2074)

Auditor: Codex `gpt-5.5` / reasoning `high`, via `scripts/run-codex.sh` (rule 53), read-only sandbox,
three rounds. Author/auditor separation held: the auditor was a separate process with no access to this
session's reasoning, and every round was asked to verify claims against the repo and the **shipped**
ReadiumCSS assets rather than against my summary.

Raw transcripts (not committed — large): `.reports/audit-r1.txt`, `.reports/audit-r2.txt`,
`.reports/audit-r3.txt` in the lane worktree.

## Production diff under audit

`android/app/src/main/kotlin/com/vreader/app/reader/EpubPreferencesMapper.kt` — two properties added to
`toEpubPreferences()`: `textAlign = ReadiumTextAlign.JUSTIFY` and `publisherStyles = false`. Every round
found the production change itself correct; all findings were about whether the **tests could tell**.

## Round 1 — 1 High, 3 Medium, 2 Low (all fixed, commit `5590d42d`)

| # | Sev | Finding | Resolution |
|---|---|---|---|
| H1 | High | Acceptance names scroll **and** paged overflow, but every connected test inherited a Scroll-pinned base — paged was entirely unverified. | Added `enEpub_pagedOverflow_justifies_andLineSpacingStillApplies`; `EpubDomProbe` gained a `scroll` parameter so a submission can no longer silently flip a paged run back to scroll. Verified `readium-paged-on` live in every state of that test. |
| M2 | Medium | The paragraph-alignment control asserted only `legacyCensus.keys - START_ALIGNMENTS == ∅`, which passes on an **empty** census. | The control must now sample the same paragraph count as the subject. |
| M3 | Medium | The E5 hyphenation control accepted any non-`auto` value, including `""` from a failed read. | Must now be a real computed `manual`/`none`. |
| M4 | Medium | E3 was enumerated over `h1`–`h6` + `small`/`sub`/`sup` but asserted on `h1`/`h2` only. | Fixture extended and each element asserted (see round 2 — the first attempt was incomplete). |
| L5 | Low | `sameContent()` claimed "same resource + element" while comparing only path + text prefix; a `p → div` fallback with the same prefix would read as the same element. | Identity now includes `tag` and `textLen`. |
| L6 | Low | The spike's helper was documented as "everything the production mapper sets except the #156 pair" but submits two variables. | Renamed `mechanismProbePrefs`, documented as the minimal probe it is; the faithful pre-#156 replica stays `legacyPreferences`. |

**Round-1 answers to the three questions the prompt required** (the auditor extracted and enumerated the
`readium-advanced-on` rules from the shipped `.aar` itself):

1. **No sixth advanced-gated effect** is reachable from the variables this mapper emits, beyond the ones
   now covered. The unset preferences (`paragraphSpacing`, `paragraphIndent`, `wordSpacing`,
   `letterSpacing`, `hyphens`, `typeScale`) keep their variable-gated rules from ever matching. It also
   confirmed `publisherStyles = false` does **not** change which stylesheets Readium injects
   (`ReadiumCSS-default.css` is governed by whether the *document* has styles) — independently pinned in
   the test by asserting the injected `sheets` list is identical across states.
2. **No assertion proves rendering from a preference object**; the weak spots were M2/M3 above.
3. **Nothing decisive is asserted on `<p>`** where `body` is the meaningful element — the CJK tests
   correctly use `body` (this book's `<p>` computes `justify` from the *publisher's* CSS in every state).

## Round 2 — H1/M2/M3/L5/L6 CLOSED; M4 **still open** (fixed in `7591cef6`)

The auditor refused to close M4 and was right: my fix used a nullable expected-value map, and the `null`
entry for `small` meant its exact assertion was **silently skipped** — `small` would have passed at any
size smaller than the publisher's. That is the same "green while wrong" shape this WI exists to prevent,
reintroduced by the fix for it. `h5`/`h6` were also still unexercised.

Closed by making every entry a mandatory `Triple` (no nullable, no skip), adding `h5`/`h6` to the fixture
and selector map, and pinning each publisher size exactly in the control arm.

## Round 3 — final: M4 CLOSED; verdict **follow-up-recommended (non-blocking)**

The auditor confirmed M4 genuinely closed, and independently verified `5/6 × root` as the correct
expectation for Chromium's `smaller` keyword (Blink `FontDescription::SmallerSize` divides by 1.2) rather
than a constant reverse-engineered from the device reading. It found nothing wrong or under-tested in the
production diff.

Its one remaining, explicitly **non-blocking** item: the `root * 0.03` / `root * 0.05` tolerances were
looser than the values they claim to pin — at 16px, ±0.48px cannot distinguish the block's computed
`1.2³ rem` from its `1.75rem` fallback declaration, nor `small`'s `5/6 rem` from a hypothetical 13px.

**Implemented** in commit `967de9bb`: both tolerances tightened to `root * 0.01` (±0.16px), which is
discriminating for both cases, and the effects class re-run on the emulator (1/1 pass, 0 skipped).
Recorded here as the auditor's verdict — `follow-up-recommended` — and **not** upgraded to `ship-as-is`,
because the lane does not certify its own fix to an auditor's finding; a fourth round would exceed the
rule-47 three-round cap.

## Test gate after the final audit-driven change

JVM `EpubPreferencesMappingTest` 16/0/0-skipped. Connected on `emulator-5554`, one class per invocation,
real EPUBs re-pushed before every run: `EpubJustifyConnectedTest` 4/0, `EpubPublisherStylesEffectsConnectedTest`
1/0, `JustificationEpubStyleSpikeTest` 3/0, plus six pre-existing EPUB suites as regression
(`EpubDisplaySettings` 1, `EpubPagedToggle` 1, `EpubReaderChrome` 3, `EpubBookmarkNav` 3, `EpubFindInBook` 6,
`EpubBilingual` 1) — 23 connected tests, 0 failures, 0 skips.

## Mutation kill map (evidence the suite discriminates)

| Mutation | Result |
|---|---|
| `textAlign = JUSTIFY`, `publisherStyles` removed | JVM RED; connected 3/3 RED |
| `publisherStyles = false`, `textAlign` removed | JVM RED; E1 RED, bug-#367 and CJK **GREEN** (the flag alone fixes line-height) |
| `lineHeight` hardcoded to 1.5 (line-height path reverted) | bug-#367 RED and CJK RED; E1 **GREEN** |
| restored | all GREEN |

The middle two are the informative ones: the suite separates the two properties rather than failing as a
block, and it distinguishes the alignment effect from the bug-#367 fix.
