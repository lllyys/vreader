---
branch: fix/issue-694-feature28-chinese-picker
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Bug #194 (GH #694) — Feature #28 Chinese Text picker XCUITest

Manual fallback per rule 47. The fix is mechanical (one-line accessibility identifier addition in production + test-side query rewrite using the same pattern as Bug #193 fix). Audit-time constraint signaled in earlier session iterations applies.

## Diagnosis

Bug #194 surfaced when Feature #45 WI-6's named Verification test plan ran end-to-end for the first time (PR #692 / v3.21.69). `Feature28ChineseConversionVerificationTests.test_verify_feature_28_chinese_text_picker_present` failed at line 56 with `XCTAssertTrue failed - Could not find section header 'Chinese Text' in settings panel after 6 swipes`.

Root cause traced to `vreader/Views/Reader/ReaderSettingsPanel.swift:535`:

```swift
Section {
    Picker("Chinese Text", selection: $store.chineseConversion) { ... }
    .pickerStyle(.segmented)
    .accessibilityLabel("Chinese text conversion")
}
```

The "Chinese Text" string is the Picker's label argument, NOT a section header (no `Section("Chinese Text") { ... }` form). With `.pickerStyle(.segmented)`, SwiftUI hides the Picker's label from the visible UI — only the segment buttons render as static text. So `panel.staticTexts["Chinese Text"]` correctly returns `exists == false`. The test was written assuming a section header that doesn't exist.

## Fix

Three-file change:

1. **`vreader/Views/Reader/ReaderSettingsPanel.swift:542`** — added `.accessibilityIdentifier("chineseTextPicker")` to the Picker (single-line addition).
2. **`vreaderUITests/Helpers/TestConstants.swift`** — added `static let chineseTextPicker = "chineseTextPicker"` constant under a new "Reader Settings — Chinese conversion (Feature #28)" MARK section.
3. **`vreaderUITests/Verification/Feature28ChineseConversionVerificationTests.swift`** — replaced the phantom-section-header `panel.staticTexts["Chinese Text"]` lookup with the descendant-by-identifier pattern (same shape as Bug #193's fix): `app.descendants(matching: .any).matching(identifier: AccessibilityID.chineseTextPicker).firstMatch`. Up-to-6 swipe loop preserved to handle the picker being below the fold for some formats.

## Files read

- `vreader/Views/Reader/ReaderSettingsPanel.swift:530-547` (the picker section)
- `vreaderUITests/Verification/Feature28ChineseConversionVerificationTests.swift` (entire file, 79 lines)
- `vreaderUITests/Reader/ChineseConversionPickerGateTests.swift:1-80` (cross-reference — uses `scrollPanelUntilLabelExists("Chinese text conversion")` which already worked; confirmed production wired `accessibilityLabel` correctly)
- `vreaderUITests/Verification/Helpers/VerificationSettingsHelper.swift:60-87` (the `scrollToSection` helper — uses `panel.staticTexts[sectionHeader]`; not changed because the verification test now bypasses it entirely)
- `vreaderUITests/Helpers/TestConstants.swift` (added the new identifier constant)

## Symbols / signatures verified

- `Picker` accepts `.accessibilityIdentifier(_:)` modifier — standard SwiftUI surface, no compatibility risk.
- `app.descendants(matching: .any).matching(identifier:).firstMatch` is the project's established element-type-agnostic query pattern (used by Feature36OPDSVerificationTests after Bug #193 fix at PR #691, commit `85ac0a3`).
- `AccessibilityID.chineseTextPicker` constant lives in `vreaderUITests/Helpers/TestConstants.swift` — same file other Reader-related identifiers live in.

## Edge cases checked

- **Picker visible on first open of settings panel**: covered by up-to-6 swipe-up retry loop preserved from original test.
- **Picker disabled for non-TXT formats**: `chineseConversionDisableReason != nil` only sets `.disabled(true)` — the picker still EXISTS in the view tree (its accessibility identifier is queryable regardless of disabled state). The contract is "picker present"; "disabled-vs-enabled" is a separate test concern not asserted by this test.
- **Identifier collision**: grepped `vreader/` and `vreaderUITests/` for any prior `chineseTextPicker` use — none found. The new identifier is unique.
- **Pre-existing test in `ChineseConversionPickerGateTests`**: uses a different query path (`scrollPanelUntilLabelExists("Chinese text conversion")` on the accessibility label) — both are valid; this fix adds an identifier-based lookup that's more stable for the Verification path's element-type-agnostic descendant query.

## Risks accepted

- **No production behavior change** other than the one added accessibility identifier; visible UI is unchanged.
- **No effect on `ChineseConversionPickerGateTests`** — it uses the accessibility label which is still wired at the same line.
- **No on-device verification this session** — bugfix cron scope ends at FIXED status flip and PR merge; close-gate device-verification picks up via the post-merge `awaiting-device-verification` label.

## Tests added or intentionally deferred

- **No new tests added** — the Bug #194 fix re-makes the existing `test_verify_feature_28_chinese_text_picker_present` pass. The RED (test fails pre-fix) was demonstrated in the prior verify-cron iteration's evidence file `dev-docs/verification/feature-45-20260515-wi-6-full-run.md` (line 56 failure). GREEN demonstrated in this PR by running the same test against the fix branch.
- **Cross-format Chinese conversion verification** (Feature #28's `test_verify_feature_28_conversion_applies_to_reader_content`) remains XCTSkip-gated on a missing CJK fixture — separate from Bug #194's contract.

## Verdict

**ship-as-is.** The fix is a 3-file, mechanical accessibility-identifier wiring matching the established Bug #193 pattern. RED→GREEN demonstrated. No regression risk to the production picker; no regression risk to the parallel ChineseConversionPickerGateTests test.
