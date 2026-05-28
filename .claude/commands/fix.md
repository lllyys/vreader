---
description: Quick bug fix for a described issue — reproduce, write a failing test (RED), fix (GREEN), refactor, verify. For the full GH-issue pipeline (tracker + Codex audit + PR + close-gate) use /fix-issue.
argument-hint: "<bug description or file>"
---

# Fix

## Context

```text
$ARGUMENTS
```

## Fixing Philosophy

**No half measures.** Every fix must be complete and correct.

### Principles

1. **Understand before fixing** — Read the code, trace the flow, identify root cause
2. **Fix the cause, not the symptom** — No band-aids, no workarounds, no "good enough"
3. **Rewrite if necessary** — Bad code deserves replacement, not patching
4. **Test-first** — Write a failing test that captures the bug, then fix, then verify green (see `.claude/rules/10-tdd.md`)
5. **Zero regressions** — Run `xcodebuild test` before declaring done
6. **Clean as you go** — If you touch it, leave it better than you found it

### Anti-patterns to Avoid

- Adding flags to bypass broken logic
- Wrapping bad code in try-catch to silence errors
- Commenting out problematic code
- Adding TODO for "later"
- Special-casing edge cases without fixing core issue
- Copy-pasting fixes across similar code

## Process

### 1. Reproduce

- Read the relevant source files. Trace the call chain from symptom to root cause.
- If the issue involves UI behavior:
  - Use **computer use + Simulator** to reproduce visually (tap, scroll, screenshot).
  - Use `sim-transfer` skill to push test files to the simulator when needed.
  - Stream live logs: `SIMCTL spawn booted log stream --predicate 'subsystem == "com.vreader.app"' --debug`
  - Use `AppLogger.<category>.debug/error()` for any new debug logging (not `print()`).

### 2. Diagnose

- Find the **root cause**, not just where it crashes.
- Check if similar patterns exist elsewhere — the same bug may lurk in related code.

### 3. Test First (RED)

- Write a failing test that captures the bug.
- Follow the pattern catalog in `.claude/rules/10-tdd.md`. VReader-specific patterns:
  - **SwiftData bug** → persistence/service test with in-memory container
  - **WKWebView bridge bug** → parser/coordinator unit test (FoliateMessageParser, FoliateViewCoordinator)
  - **ViewModel bug** → Swift Testing async test with `@MainActor` and mocks
  - **Utility bug** → parameterized Swift Testing `@Test(arguments:)` covering the broken case
  - **PDFKit bug** → annotation/page mapping test
  - **TextKit/TXT bug** → offset translation, Unicode/CJK boundary test
- Exception: visual-only bugs don't need unit tests — use manual QA on device instead.

### 4. Fix Properly (GREEN)

- Address the root cause. Rewrite if the existing code is fundamentally flawed.
- Keep the diff minimal and focused — don't refactor unrelated code.
- Follow project conventions:
  - Keep files under ~300 lines
  - Escape all strings before `evaluateJavaScript()` via `FoliateJSEscaper`
  - Use `@Observable` + `@MainActor` for ViewModels
  - Use `Locator.validated()` for position construction

### 5. Refactor

- Clean up without changing behavior. Tests must still pass.
- Remove dead code. Update comments if they're now stale.

### 6. Verify

- Run tests:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:vreaderTests
  ```
- Update trackers:
  - Update bug status in `docs/bugs.md` (TODO → FIXED)
  - Update `docs/architecture.md` if component communication changed

### When to Rewrite vs Patch

**Rewrite when:**

- The existing code is fundamentally flawed
- Patching would add complexity
- The fix requires understanding fragile logic
- Similar bugs have occurred in this code before

**Patch only when:**

- The code is sound but has a small oversight
- The fix is isolated and obvious
- Rewriting would introduce unnecessary risk
