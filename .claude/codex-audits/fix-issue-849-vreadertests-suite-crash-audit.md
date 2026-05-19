---
branch: fix/issue-849-vreadertests-suite-crash
threadId: 019e3daa-8dfc-7ce1-9627-bd41f55892e2
rounds: 3
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit — issue #849 (bug #221): vreaderTests full-suite flaky test-host crash

## Bug & root cause

`xcodebuild test -only-testing:vreaderTests` flakily crashes the test host
once per full-suite run (`Restarting after unexpected exit, crash, or test
timeout`), overall verdict `** TEST FAILED **` despite zero assertion failures.

The bug report's hypothesis (off-main `@Observable`/`@Published` mutation in the
backup / `SelectiveRestoreCoordinator` area) was a **red herring**. The full
suite was reproduced with isolated DerivedData, and the actual crash backtrace
is unambiguous:

```
Main Thread Checker: UI API called on a background thread: -[UIReferenceLibraryViewController initWithTerm:]
PID: 69548, TID: 19371663, Queue name: com.apple.root.user-initiated-qos.cooperative
Backtrace:
5  vreader.debug.dylib  $sSo32UIReferenceLibraryViewControllerC4termABSS_tcfcTO
6  vreader.debug.dylib  $sSo32UIReferenceLibraryViewControllerC4termABSS_tcfC
7  vreader.debug.dylib  $s7vreader16DictionaryLookupO14viewController3for...FZ
8  vreaderTests         $s12vreaderTests016DictionaryLookupB0V29viewController_createsForWordyyF
```

`DictionaryLookup.viewController(for:)` constructs a
`UIReferenceLibraryViewController` (a `UIViewController`). `DictionaryLookup`
was a plain `enum` with no actor isolation, and `DictionaryLookupTests` was a
non-`@MainActor` `@Suite`, so Swift Testing's parallel scheduler dispatched
`viewController_createsForWord` onto a background cooperative thread. UIKit's
Main Thread Checker aborts the process when a `UIViewController` initialiser
runs off-main. Flaky because the scheduler nondeterministically assigns the
test to whatever cooperative thread is free — under the saturated full-suite
parallel run it lands off-main; run in isolation it happens to land on main.

The `[SelectiveRestoreCoordinator]` log lines and
`[SwiftUI] Publishing changes from background threads` warnings the bug report
cited are unrelated suites running concurrently with the crash — warnings, not
the abort.

## Fix

- `vreader/Services/DictionaryLookup.swift` — `@MainActor` on the two
  UIKit-touching members: `canLookUp(_:)` (calls
  `UIReferenceLibraryViewController.dictionaryHasDefinition`, main-thread-only)
  and `viewController(for:)` (constructs the view controller). `extractWord`
  and the menu-title `String` constants stay non-isolated — they touch no
  UIKit. This makes any synchronous off-main call a Swift 6 compile error.
- `vreaderTests/Services/DictionaryLookupTests.swift` — `@MainActor` on the
  `@Suite` so the UIKit-touching tests run deterministically on the main
  thread (mirrors the bug #216 / #838 `PDFViewBridgeThemeTests` precedent).
  Strengthened `viewController_createsForWord` to assert a fresh non-shared
  instance per call.

## Round-by-round findings

### Round 1
| file:line | severity | issue | resolution |
|---|---|---|---|
| DictionaryLookupTests.swift (new tests) | Low | `viewController_isConstructedOnMainThread` / `canLookUp_runsOnMainThread` are wiring-only — `#expect(Thread.isMainThread)` is tautological under a `@MainActor` suite and cannot assert the compile-time annotation. | FIXED — removed both wiring-only tests. The regression guard is the compile-time `@MainActor` on the production member; documented in a comment block instead. |

Codex confirmed: correctness of the fix (member-level `@MainActor` fixes the
root cause; off-main sync call → compile error; async `await` is a safe hop),
no compile breakage at the three production call sites
(`DictionarySheet.makeUIViewController` is `@MainActor` via
`UIViewControllerRepresentable`; `ReaderContainerView` uses only non-isolated
`extractWord`; `TXTBridgeShared` reads only the `String` constants), the
member-level granularity is the right boundary, and no other test/production
path constructs `UIReferenceLibraryViewController` off-main.

### Round 2
| file:line | severity | issue | resolution |
|---|---|---|---|
| DictionaryLookupTests.swift:147 | Low | The replacement comment overstated the guard — "if either `@MainActor` is dropped the suite won't compile" is false: dropping `@MainActor` from the production member while keeping it on the suite still compiles. | FIXED — comment reworded to separate the two distinct guarantees (production `@MainActor` = compile-time call-site protection; suite `@MainActor` = these tests stay on-main). |

### Round 3
Zero findings. **Ship-as-is.**

## Verdict

Ship-as-is. The fix targets the actual root cause (UIKit construction off the
main thread), is isolation-correct under Swift 6, breaks no call sites, and is
guarded going forward by the production `@MainActor` annotation (any future
off-main caller is a compile error). 3 audit rounds, all findings resolved.
