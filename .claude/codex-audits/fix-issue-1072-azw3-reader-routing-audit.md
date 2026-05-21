---
branch: fix/issue-1072-azw3-reader-routing
threadId: 019e4756-1a31-7461-bcaa-fe3f74e58cf9
rounds: 4
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex Audit — Bug #246 / GH #1072

**Branch**: `fix/issue-1072-azw3-reader-routing`
**Date**: 2026-05-21
**Author**: Claude Code (worktree agent-a13af2ca5c0a2caf3)
**Codex model**: default (ChatGPT-account-compatible)
**Threads**:
- Round 1: `019e4756-1a31-7461-bcaa-fe3f74e58cf9`
- Round 2: `019e4758-14c7-7713-809b-fcbaeb1e339e`
- Round 3: `019e4759-d935-77a0-8f0a-2feefc3c8039`
- Round 4: `019e475b-792d-7ca0-8ae7-29c24691196c`

## Scope

Two files in the diff:
- `vreader/Views/Reader/ReaderContainerView.swift` — production: `engineReaderView` body rewritten to route off `fingerprint.format` (the typed `BookFormat` parsed from the canonical `fingerprintKey` at the call site) instead of `book.format.lowercased()` (a parallel String `@Model` column that can drift from the canonical key).
- `vreaderTests/Views/Reader/ReaderContainerViewEngineDispatchTests.swift` — new regression guard `engineDispatchReadsCanonicalFingerprintFormat()` + one comment update on `unsupportedFormatViewMovedIntoContainer()`.

## Round 1 (initial audit)

**Finding** (Low): "the new regression guard is too syntactic — it only forbids the exact substring `BookFormat(rawValue: book.format.lowercased())` and separately looks for any `fingerprint.format` mention, so an equivalent dispatch bug could slip through via a helper/temporary or a different `book.format` normalization while the test still passes."

**Remediation**: tightened test — positive assertion pins exact dispatch expression `ReaderEngine.resolve(format: fingerprint.format)`; negative assertion bans **any** `book.format` substring inside the function body.

## Round 2

**Finding** (Medium): "the test inspects `prefix(1500)` after `func engineReaderView`, but the current production function is already 1838 bytes long — the 'ban any `book.format`' assertion does not actually cover the full function body today. A future regression can move a stale-format read into the tail of the function and still pass this guard."

**Finding** (Low): textual sentinel vs. semantic. Accepted with rationale — every existing test in `ReaderContainerViewEngineDispatchTests` is source-text-based (this is the established pattern in the file).

**Remediation** (Medium): replaced the fixed `prefix(1500)` slice with a bound-on-next-sibling-declaration scan. Earliest match of `// MARK: - Error / Unsupported`, `var fingerprintErrorView`, or `func unsupportedFormatView` (whichever first). Scales naturally as the function grows.

## Round 3

**Finding** (Low): "the new bound is still an unconstrained substring search, so it can terminate `bodyText` early if `engineReaderView` later gains any inline comment, string literal, or helper call mentioning `fingerprintErrorView` or `unsupportedFormatView`."

**Remediation**: anchored each cut-marker to a top-level declaration form — `\n    // MARK: - Error / Unsupported Views`, `\n    var fingerprintErrorView`, `\n    func unsupportedFormatView`. An inline mention inside the body has no leading `\n    ` prefix and cannot cut the bound short.

## Round 4

**Result**: **no findings**. The round-3 marker fix is sufficient. Verdict: ship-as-is. Residual risk noted (general source-text tests are formatting-sensitive; will need maintenance if the file is reformatted) is an acceptable tradeoff for this class of regression guard, not a follow-up-commit-worthy issue.

## Final verdict

**ship-as-is** (4 rounds, all findings addressed within the same PR).

## Test gate

- `xcodebuild test -only-testing:vreaderTests/ReaderContainerViewEngineDispatchTests`: 11/11 tests PASS, 0.028s.
- `xcodebuild test -only-testing:vreaderTests` full suite: 6978 tests in 694 suites PASS, 38.8s.

## Manual reproduction post-fix

- `mini-azw3` fixture (Edgar Allan Poe, "The Masque of the Red Death"): opens via Foliate → screenshot `dev-docs/verification/artifacts/bug-246-postfix-azw3-foliate-20260521.png`.
- User's CJK AZW3 (`Bei Tao Yan De Yong Qi - Zi Wo.azw3`, 6.3 MB, Mobipocket v8): opens via Foliate → screenshot `dev-docs/verification/artifacts/bug-246-postfix-user-azw3-20260521.png`.

Both books route to `FoliateBilingualContainerView`, the Foliate-js renderer paints, the DebugBridge snapshot reports `format: "azw3"` with `ttsState: "idle"` (probe registered).
