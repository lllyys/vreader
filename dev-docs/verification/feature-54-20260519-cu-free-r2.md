---
kind: feature
id: 54
status_target: VERIFIED
commit_sha: 9bd777b71c15c07260d90a46ec5a86564f8c96a4
app_version: 3.36.2 (build 517)
date: 2026-05-19
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: partial
---

# Feature #54 — Remove Native/Unified reading mode toggle (CU-free XCUITest verification, round 2)

Round-2 Gate-5 verification for feature #54. Builds on the two prior
evidence files:

- `feature-54-20260519.md` — `result: partial`. Criteria 1/4/5 PASS;
  criterion 2 verified only at the integration boundary because the
  headless `simctl openurl` DebugBridge path could not commit the
  `NavigationStack` reader-open push without a driven display.
- `feature-54-20260519-cu-free.md` — `result: partial`. A CU-free
  XCUITest suite (`Feature54ReadingModeRemovalVerificationTests`, 4
  tests) closed the headless-navigation gap and verified criteria 1,
  2-**structural**, 5 end-to-end through the live reader UI. Criterion
  2's **transform-application** half (a configured replacement rule
  actually showing up *applied* in the rendered MD reader text) was
  still only covered at the unit/integration boundary, never observed
  in the live reader UI.

This round-2 file records ONE addition: the criterion-2
transform-application UI gap is now closed CU-free. The XCUITest suite
was extended from 4 to 5 tests; the new test
`test_verify_feature_54_replacement_rule_applies_in_native_md` drives
the full path end-to-end and asserts the replacement is *applied* in
the rendered MD reader text.

## Criterion-3 scope determination (governs the status flip)

**Determination: criterion 3 (replacement rules work in native EPUB
without a mode switch) is a binding feature #54 acceptance GATE. It is
genuinely unimplemented. Therefore #54 CANNOT reach `VERIFIED` now and
the result is `partial`.**

Reasoning, from the authoritative sources:

1. **The feature row's Acceptance criteria** (`docs/features.md` row 54)
   reads, verbatim: *"no picker in normal use; **replacement rules work
   in native EPUB and MD** without mode switch; readingMode key removed
   with migration; all existing reader features unchanged."* Native
   **EPUB** is textually inside the acceptance contract.

2. **GH issue #609's body** (the mirror) lists, verbatim: *"Replacement
   rules apply in **native EPUB and MD** without switching modes"* and
   names **Bug #128 ("replacement rules no-op in native EPUB")** in its
   Related section. EPUB is in the contract there too.

3. **The plan** (`dev-docs/plans/20260518-feature-54-remove-reading-mode-toggle.md`)
   does NOT remove criterion 3 from the contract — it **defers its
   implementation** to "Phase D" (§4 Phase D / D-1, §2.0 finding 4,
   §2d, §3 rejected-alt C, §6 conclusion). The plan's own §4 framing is
   explicit: Phase D "is documented so the deferred scope is explicit"
   and "when #42 reaches its relevant WIs, **file a follow-up to land
   D-1/D-2**". Phase D is therefore deferred **#54 scope**, not a
   distinct out-of-#54 feature. D-1 (native EPUB replacement rules) is
   "**Blocked on #42 Gate-3 ratification (G1) and the engine
   decision**" — and feature #42 is human-ratification-blocked.

4. **`SCHEMA.md` result semantics** are decisive: *"Every criterion in
   the plan must appear; 'deferred' or 'blocked' counts as fail unless
   the row explains why and the `result` field is `partial`"*, and
   *"`partial` … Tracker status may NOT move to `VERIFIED`"*.

So: criterion 3 is in the acceptance contract, is deferred-not-removed,
and has not shipped. The `result` is `partial`; the row stays `DONE`,
not `VERIFIED`. This is identical to the conclusion both prior evidence
files reached — round 2 does not change it, because round 2 verifies
only criteria #54 actually shipped; it cannot verify the unimplemented
Phase D EPUB work. **The `VERIFIED` flip awaits Phase D shipping
criterion 3 (a follow-up unblocked by feature #42) plus a follow-up
acceptance pass.**

> `status_target: VERIFIED` in the frontmatter records the *eventual*
> target this evidence chain works toward (per `SCHEMA.md`'s required
> frontmatter). The operative field is `result: partial`, which holds
> the row at `DONE`.

## Acceptance criteria

| # | Criterion (from the feature row) | Observed | Result |
|---|---|---|---|
| 1 | No reading-mode picker in normal use | Unchanged from `feature-54-20260519-cu-free.md`: the 4 picker-absence tests still pass at v3.36.2 — for each openable format (TXT/EPUB/MD) the Display panel is opened and scrolled top-to-bottom (11 positions, full 12-section panel) with NO "Reading Mode" / "Tap Zones" section header and NO "Native"/"Unified" segment button found at any position. | **PASS** (end-to-end UI) |
| 2 | Replacement rules work in native EPUB **and** MD without a mode switch — **MD half** | **Round-2 upgrade — transform-application now observed end-to-end in the live UI.** `test_verify_feature_54_replacement_rule_applies_in_native_md` (1) seeds the `.mdTOC` Markdown book, (2) creates a global content-replacement rule ("Introduction" → "Prologue") by typing into the live Settings → Replacement Rules edit-sheet `TextField`s and tapping Save, (3) opens the MD book — `markdownNative` engine, NO mode switch (feature #54 removed that control), (4) reads the rendered MD reader text (a `UITextView` via `TXTTextViewBridge`, so XCUITest-queryable) and asserts the replacement is **APPLIED**: "Prologue" present, "Introduction" absent. The MD book opens into the native engine and renders with no Reading Mode picker (structural half, also covered by `test_verify_feature_54_md_native_engine_no_reading_mode_picker`). The 20 real-boundary integration tests (`MDReaderReplacementRulesTests`, `MDReplacementRuleFetcherTests`) remain as the transform-correctness backstop. | **PASS** (end-to-end UI — transform applied) |
| 3 | Replacement rules work in native EPUB without a mode switch — **EPUB half** | DEFERRED to Phase D (D-1) by the Gate-1/Gate-2 plan — native EPUB renders by `loadFileURL` of on-disk XHTML with no Swift string seam; it needs CFI-safe JS text-node preprocessing built against feature #42's engine decision, and feature #42 is human-ratification-blocked. Not implemented → no test can exercise it. **This criterion IS part of #54's acceptance contract** (see the scope determination above), so its non-implementation holds the `result` at `partial` and the row at `DONE`. | DEFERRED (by plan, in-contract → keeps result `partial`) |
| 4 | `readerReadingMode` key removed with migration | Unchanged — verified device-side + by 14 `ReadingModeMigration` unit tests in `feature-54-20260519.md`: after launch `readerReadingMode` is absent from `com.vreader.app.plist`; per-book JSON carries no `readingMode` field. A UserDefaults / launch-migration concern with no UI surface — outside XCUITest scope, no re-verification needed. | **PASS** (device + unit — prior evidence) |
| 5 | All existing reader features unchanged | Unchanged from `feature-54-20260519-cu-free.md`: the 3 per-format engine tests still pass at v3.36.2 — TXT/MD open into a `UITextView`/`UITableView` (`textNative`/`markdownNative`), EPUB into a `WKWebView` (`epubWKWebView`); reader chrome present. `ReaderEngine.resolve` dispatch routes every openable format to its own native host after the `readingMode`-branch deletion. PDF (`pdfKit`) and AZW3/MOBI (`foliateWeb`) have no openable debug seed; their routing is covered by `ReaderEngineTests`. | **PASS** (end-to-end UI for TXT/EPUB/MD; unit for PDF/AZW3) |

`result: partial` — criteria 1, 2 (MD, now including transform
application), 4, 5 PASS end-to-end; criterion 3 (native EPUB
replacement rules) is an in-contract acceptance criterion DEFERRED by
the plan to Phase D (blocked on feature #42) and not implemented.
Per `SCHEMA.md` a `partial` result cannot flip the row to `VERIFIED`;
**the row stays `DONE`.**

## Commands run

```bash
# Worktree: .claude/worktrees/agent-aa5361a5ac42145db
# Branch:   docs/feature-54-verification (rebased onto origin/main @ 84aee57)
# App:      v3.36.2 (build 517)

# Run the full CU-free verification suite on iPhone 17 Pro Simulator
# (UDID 61149F0E-... pinned for explicit simulator ownership — rule 48).
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,id=61149F0E-DC18-4BE2-BB37-52659F1F4F62' \
  -only-testing:vreaderUITests/Feature54ReadingModeRemovalVerificationTests
# → Executed 5 tests, with 0 failures in 158.388 seconds. ** TEST SUCCEEDED **
```

Per-test result (full suite — the 5th is the round-2 addition):

```
test_verify_feature_54_epub_native_engine_no_reading_mode_picker  passed (31.4s)
test_verify_feature_54_md_native_engine_no_reading_mode_picker    passed (31.4s)
test_verify_feature_54_no_reading_mode_section_in_display_panel   passed (30.2s)
test_verify_feature_54_replacement_rule_applies_in_native_md      passed (34.1s)  ← round-2 addition
test_verify_feature_54_txt_native_engine_no_reading_mode_picker   passed (31.3s)
```

The round-2 test was also run standalone twice to confirm it is not
flaky — green both times (34.0s, 34.1s).

Transform-correctness integration tests (criterion 2's behavioral
backstop), from the prior evidence file's `Commands run`:

```bash
xcodebuild test \
  -only-testing:vreaderTests/MDReaderReplacementRulesTests \
  -only-testing:vreaderTests/MDReplacementRuleFetcherTests \
  -only-testing:vreaderTests/MDFileLoaderTests \
  -only-testing:vreaderTests/ReaderEngineTests \
  -only-testing:vreaderTests/ReadingModeMigrationTests
# → 56 tests in 5 suites passed (prior evidence file).
```

## Observations

- **The criterion-2 transform-application gap is now genuinely closed
  CU-free.** The prior CU-free file verified that the MD book opens
  into the `markdownNative` engine with no mode switch (the
  *structural* contract) and leaned on the 20 integration tests for
  transform correctness. The round-2 test goes further: it drives a
  configured replacement rule from the live Settings UI all the way to
  the rendered MD reader text. Because the MD reader renders through a
  `UITextView` (`TXTTextViewBridge`), its text content is queryable by
  XCUITest — so "the rendered text contains 'Prologue' and not
  'Introduction'" is a real end-to-end assertion of "replacement rules
  work in native MD", not a unit stub. The end-to-end path exercised:
  Settings → Replacement Rules UI → `ContentReplacementRule` insert →
  `MDReaderContainerView.task` → `MDReplacementRuleFetcher` → real
  `MDFileLoader.load` → real `ReplacementTransform` → rendered text.

- **The `.mdTOC` seed forces a disk-backed SwiftData store** —
  `VReaderApp` whitelists `seedMDTOC` (alongside `seedWarAndPeace`,
  `seedEPUBFixture`, etc.) for a disk-backed `ModelConfiguration` so
  terminate-relaunch persistence tests work (Bug #151). A side effect:
  `ContentReplacementRule` rows persist across test runs (the
  `--reset-preferences` flag only clears UserDefaults, not SwiftData).
  The round-2 test handles this itself — `clearExistingReplacementRules`
  deletes any pre-existing rules through the ReplacementRulesView's
  swipe-to-delete before adding its own, keeping the test deterministic
  and idempotent. This is a test-hygiene measure, not a product bug; it
  did not warrant a production change.

- **Sheet-dismiss + post-sheet hittability needed care.** Two
  XCUITest-only timing realities surfaced while building the test and
  were handled in `vreaderUITests/` helpers (no production change):
  (1) the SettingsView sheet's interactive swipe-down dismiss must
  start *inside* the sheet's top strip (≈y=0.12), not in the
  status-bar band above the sheet — a higher start point does not
  register on the sheet's presentation controller; (2) a library book
  card can be laid out with a valid frame yet report a non-hittable
  `{-1,-1}` hit point for a short window after a sheet dismiss, so the
  post-dismiss open helper taps the card's frame centre by coordinate
  when it is not yet hittable.

- **No feature #54 production code was modified.** This is a
  verification-only change: `vreaderUITests/` (the test suite) +
  `dev-docs/` (this file) + `project.yml` / `pbxproj` (version bump).
  The `check_codex_audit_artifact.sh` merge hook is not triggered (no
  `vreader/` or `vreaderTests/` Swift file touched).

- **Stale-doc note (not a #54 regression, filed separately).**
  `ReplacementRulesView.nativeModeBannerText` still reads "Switch from
  the reader's Settings → Reading Mode" — but feature #54 removed the
  Reading Mode picker, so that banner now points users at a control
  that no longer exists. This is a documentation-copy defect on an
  existing surface, outside feature #54's acceptance criteria; it has
  been filed as a separate bug rather than fixed here (verification
  scope = verify, not fix).

## Artifacts

- Verification suite (extended this round to 5 tests):
  `vreaderUITests/Verification/Feature54ReadingModeRemovalVerificationTests.swift`
- Prior evidence files:
  `dev-docs/verification/feature-54-20260519.md` (DebugBridge headless),
  `dev-docs/verification/feature-54-20260519-cu-free.md` (CU-free round 1).
- `.xcresult` bundles from the passing runs under
  `~/Library/Developer/Xcode/DerivedData/vreader-*/Logs/Test/`.
