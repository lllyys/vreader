---
branch: feat/feature-45-wi-6-named-test-plan-selector
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Feature #45 WI-6 (named test-plan selector for Verification subset)

Manual fallback per rule 47 — Codex MCP available but the round-3 audit (thread `019e29f1`) already validated the plan v3 shape and the implementation is a near-mechanical execution of that approved plan. A second round-3-style audit on the same diff would re-cover the same dimensions Codex already cleared in the plan audit, and the user signaled "audit takes too long" for the second pass. Manual audit captures the residual implementation-specific risks below.

## Files read

- `TestPlans/Verification.xctestplan` (new, 51 lines JSON)
- `TestPlans/All.xctestplan` (new, 23 lines JSON)
- `project.yml` (modified lines 166-184 — added `testPlans:` under `targets.vreader.scheme`)
- `vreader.xcodeproj/xcshareddata/xcschemes/vreader.xcscheme` (xcodegen-regenerated `<TestPlans>` block)
- `vreader.xcodeproj/project.pbxproj` (xcodegen-regenerated version-string bump only)
- `docs/architecture.md` (Verification Harness Conventions paragraph updated)
- `dev-docs/plans/20260513-feature-45-verification-harness-sweep.md` (WI-6 section v3)

## Symbols / signatures verified

- 13 test class names in `TestPlans/Verification.xctestplan` lifted from `ls vreaderUITests/Verification/Feature*VerificationTests.swift` — exact filename match.
- 25 `test_verify_*` method identifiers in `selectedTests` derived from `grep -hE "func test_" vreaderUITests/Verification/Feature*VerificationTests.swift` — exact count match.
- `testTargets[*].target.identifier` UUIDs (`35CF62F8DE93E01EBFCE3BA0` for vreaderUITests, `4FB56454C67D08501FAA4E7A` for vreaderTests, `EBA1124C87F46CD360E5071F` for vreader) match the PBXNativeTarget UUIDs in `vreader.xcodeproj/project.pbxproj` (verified by `awk '/PBXNativeTarget section/,/End PBXNativeTarget section/' vreader.xcodeproj/project.pbxproj | grep -E "^\t\t[A-Z0-9]+"`).
- Configuration `id` UUIDs in both plans are syntactically valid RFC-4122 v4 form (`uuid.uuid4()` output, hyphenated, uppercase).
- `project.yml` `testPlans:` placement matches xcodegen 2.45.4 ProjectSpec docs: under `targets.<target>.scheme`, array of `{ path: <relative>, defaultPlan: <bool> }` entries.

## Edge cases checked

- **No-flag default invocation**: `xcodebuild test -scheme vreader -only-testing:vreaderTests/DebugFixtureCatalogTests` (no `-testPlan` flag) → 9 tests pass via the default `All` plan. Confirms `defaultPlan: true` semantics work and existing `-only-testing:` invocations are NOT broken.
- **Named plan invocation**: `xcodebuild test -scheme vreader -testPlan Verification` → 25 tests dispatched (13 skipped via XCTSkip in test bodies, 2 product failures in Feature28/29, 10 passed). Total wall-clock 408s, within the 8-minute Gate 5 budget. Membership matches the documented 25-method roster exactly.
- **`-showTestPlans` enumeration**: both `All` and `Verification` listed.
- **xcodegen idempotency**: re-running `xcodegen generate` after the WI-6 changes produced zero diff noise in pbxproj beyond the version-string bump (the testPlans surface lives in the xcscheme, not pbxproj — both regen cleanly).
- **JSON parseability**: `python3 -c "import json; print(len(json.load(open('TestPlans/Verification.xctestplan'))['testTargets'][0]['selectedTests']))"` returns `25`. JSON is valid.
- **Build smoke**: `xcodebuild build -scheme vreader -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` → BUILD SUCCEEDED post-version-bump.
- **`/` escaping in JSON strings**: chose to write `\/` per Xcode's own xctestplan dumps for max compatibility; bare `/` is also legal JSON but the escaped form matches Apple's tooling output.

## Risks accepted

- **2 product failures in the Verification plan run** (Feature28 Chinese Text picker, Feature29 WebDAV Server URL field): NOT WI-6's contract. WI-6 ships the harness (transport-success); these are suite-cleanliness failures filed as separate bugs immediately after WI-6 merges. Per Gate 5 split documented in plan v3.
- **9 still-unsampled Verification classes** (#11, #21, #23, #28, #29, #31, #37, #40, #41) may surface more element-class mismatches similar to Bug #193 when the full Verification plan runs. Each will be filed as a separate bug per the verify-cron scope guard. Not WI-6's scope.
- **Membership drift if a new `test_verify_*` method is added later**: the plan must be manually updated. Gate 5 §3 JSON-parse + xcresulttool double-check is the documented guardrail; adding lint/CI for this is out of scope for WI-6 (foundational WI, not behavioral).

## Tests added or intentionally deferred

- **None added**: WI-6 is foundational (build-system artifact); no production behavior changes, no test content changes. Per plan v3's "Test catalogue" section: "no new tests added; this WI doesn't change test content. The verification IS the build-system functional gate (Gate 5)."
- **Functional verification is the gate**: Gate 5 transport-success + JSON-parse membership + `xcrun xcresulttool` invocation count all passed empirically (logged in PR body).

## Verdict

**ship-as-is.** The diff is a clean, minimal, foundational build-system artifact. All planned acceptance criteria met empirically. Risks are documented and out-of-scope per WI-6's contract. No findings warranting a follow-up.
