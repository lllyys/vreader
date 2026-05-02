# 10 - TDD Workflow

Test-Driven Development for vreader. Tests live in `vreaderTests/`. Run via `xcodebuild test`. Coverage thresholds are not currently gated structurally; discipline is the gate.

**vreader uses Swift Testing as the primary framework** (`import Testing`, `@Test`, `#expect`). XCTest is used only for tests that need `XCTestExpectation` (notification / async-callback timing) or `XCUnwrap`-style helpers — minority of tests, ~5% of the suite. New tests should default to Swift Testing unless they specifically need XCTest's expectation/notification machinery.

## Core Discipline: RED → GREEN → REFACTOR

1. **RED** — Write a failing test that describes the expected behavior.
2. **GREEN** — Write the minimum code to make the test pass.
3. **REFACTOR** — Clean up without changing behavior. Tests must still pass.

Never skip RED. If you write code first, you don't know your test actually catches regressions.

## When Tests Are Required

| Category          | Required?      | Examples                                                                  |
| ----------------- | -------------- | ------------------------------------------------------------------------- |
| Services / actors | **ALWAYS**     | `PersistenceActor`, `BookImporter`, `TXTService`, encoding detectors      |
| Pure utilities    | **ALWAYS**     | `DocumentFingerprint`, `Locator`, parsers, formatters                     |
| ViewModels        | **ALWAYS**     | State transitions, async flows, error paths                               |
| Bug fixes         | **ALWAYS**     | Regression test that fails on the pre-fix commit                          |
| Edge cases        | **ALWAYS**     | Empty input, nil, boundary values, Unicode/CJK, RTL, race conditions      |
| SwiftUI views     | Case-by-case   | Test behavior (callbacks, observable state), not pixel rendering          |
| Reader bridges    | Case-by-case   | Test message parsing, JS escaping, locator math — not WebView interaction |
| Pure data models  | If non-trivial | `BookRecord`, `HighlightRecord` — test invariants, not getters            |

## Pattern Catalog

The patterns below show XCTest first because vreader's actor/ViewModel/notification tests rely on `XCTestCase`-specific helpers (`XCTestExpectation`, `XCUnwrap`, async `setUp`, isolation pinning). For straightforward tests, prefer Swift Testing.

### 0. Swift Testing (default for new tests)

```swift
import Testing
@testable import vreader

@Suite("DocumentFingerprint")
struct DocumentFingerprintSuite {
    @Test func canonicalKeyRoundTrips() {
        let fp = DocumentFingerprint(contentSHA256: "abc...", fileByteCount: 1024, format: .epub)
        let parsed = DocumentFingerprint(canonicalKey: fp.canonicalKey)
        #expect(parsed == fp)
    }

    @Test(arguments: [
        ("hello world", 11),
        ("",            0),
        ("héllo",       6),  // 5 chars but 6 UTF-8 bytes
    ])
    func byteCountMatchesUTF8(_ input: String, _ expected: Int) {
        #expect(input.utf8.count == expected)
    }
}
```

**Use Swift Testing for:** pure functions, value types, parameterized tests, anything that doesn't need XCTest's async-callback machinery.

**Use XCTest (patterns 1-5 below) for:** actor tests with async setUp, MainActor-isolated ViewModels, notification observers needing `XCTestExpectation`, anywhere you need `XCUnwrap` over `#require`.

### 1. Actor / Service Tests

```swift
import XCTest
@testable import vreader

final class PersistenceActorTests: XCTestCase {
    private var container: ModelContainer!
    private var actor: PersistenceActor!

    override func setUp() async throws {
        let schema = Schema(SchemaV4.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        actor = PersistenceActor(modelContainer: container)
    }

    func test_insertBook_dedupesByFingerprintKey() async throws {
        let record = makeBookRecord(sha: String(repeating: "a", count: 64))
        let first = try await actor.insertBook(record)
        let second = try await actor.insertBook(record)
        XCTAssertEqual(first.fingerprintKey, second.fingerprintKey)
    }
}
```

**Key patterns:**

- In-memory `ModelContainer` for SwiftData isolation.
- `setUp() async throws` to construct dependencies.
- Test public actor methods directly — actors serialize, no manual locking.

### 2. ViewModel Tests

```swift
@MainActor
final class LibraryViewModelTests: XCTestCase {
    func test_deleteBook_removesFromBooksArray() async {
        let persistence = MockPersistence()
        let viewModel = LibraryViewModel(persistence: persistence, importer: ..., preferenceStore: ...)
        await viewModel.loadBooks()
        await viewModel.deleteBook(fingerprintKey: "key-1")
        XCTAssertFalse(viewModel.books.contains { $0.fingerprintKey == "key-1" })
    }
}
```

**Key patterns:**

- `@MainActor` on the test class for ViewModels marked `@MainActor`.
- Inject mocks via protocol parameters (`LibraryPersisting`, `BookImporting`).
- Assert on observable state, not internal helpers.

### 3. Pure-Function Tests

```swift
final class DocumentFingerprintTests: XCTestCase {
    func test_canonicalKey_roundTrips() {
        let fp = DocumentFingerprint(contentSHA256: "abc...", fileByteCount: 1024, format: .epub)
        let parsed = DocumentFingerprint(canonicalKey: fp.canonicalKey)
        XCTAssertEqual(parsed, fp)
    }
}
```

**Key patterns:**

- Pure functions = no setUp, no mocks.
- Use `XCTAssertEqual(_:_:_)` for `Equatable` types.
- Cover all branches in one test class via `func test_` methods.

### 4. Async / Concurrency Tests

```swift
@MainActor
func test_bridge_concurrentCalls_doNotInterleave() async {
    let bridge = MyBridge(...)
    async let a = bridge.handle(...)
    async let b = bridge.handle(...)
    _ = await (a, b)
    // assert ordering invariants on the recorded calls
}
```

**Key patterns:**

- `async let` for concurrent calls; `await (a, b, ...)` to join.
- For deterministic timing, use a clock probe pattern (see `DebugBridgeTests.SlowDebugBridgeContext`).
- Avoid `Task.sleep` for synchronization; use `XCTestExpectation` + `fulfillment(of:timeout:)`.

### 5. Notification / Bridge Tests

```swift
func test_handler_postsExpectedNotification() async {
    let exp = expectation(description: "notification posted")
    nonisolated(unsafe) var receivedKey: String?
    let token = NotificationCenter.default.addObserver(
        forName: .myNotification, object: nil, queue: .main
    ) { notification in
        receivedKey = notification.userInfo?["key"] as? String
        exp.fulfill()
    }
    defer { NotificationCenter.default.removeObserver(token) }

    handler.fire(key: "test-key")
    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(receivedKey, "test-key")
}
```

**Key patterns:**

- `XCTestExpectation` + `fulfillment(of:timeout:)` — never bare `sleep`.
- Always `removeObserver` in `defer`.
- `nonisolated(unsafe)` to capture into a notification closure that runs on a different queue.

## Anti-Patterns — What NOT to Do

| Anti-pattern                       | Why it's wrong                                 | Do this instead                                              |
| ---------------------------------- | ---------------------------------------------- | ------------------------------------------------------------ |
| Write code first, tests after      | You can't verify your test catches regressions | RED first — always                                           |
| `func test_loadsWithoutCrashing()` | Tests nothing meaningful                       | Test specific observable behavior                            |
| Testing `private` implementation   | Breaks on refactor                             | Test public API only                                         |
| Mocking everything                 | Tests prove nothing                            | Mock boundaries (network, filesystem), not internal logic    |
| Skipping edge cases                | Bugs live at boundaries                        | Empty input, nil, max values, concurrent access, Unicode/CJK |
| Bare `Task.sleep(...)` for sync    | Flaky in CI                                    | `XCTestExpectation` with timeout                             |
| `XCTAssertNotNil(x); x!.foo()`     | Crashes on failure                             | `let x = try XCTUnwrap(opt); x.foo()`                        |
| Tests that depend on order         | Flaky                                          | Reset state in `setUp`; never share state across tests       |

## Test Commands

```bash
# Build then run unit tests only (skip UI tests during dev)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:vreaderTests

# Single test class (faster iteration)
... -only-testing:vreaderTests/MyClassTests

# Single test method
... -only-testing:vreaderTests/MyClassTests/test_specificThing
```

The TDD Guardian config at `.claude/tdd-guardian/config.json` invokes the same `xcodebuild test` flow.

## File Placement

- Tests go next to the production code, mirroring the source tree:
  `vreader/Services/Foo/Bar.swift` → `vreaderTests/Services/Foo/BarTests.swift`
- Larger test suites use a `__tests__` or feature subdirectory.
- Shared test helpers go in `vreaderTests/Helpers/` (e.g., `CollectionTestHelper`).

## Exceptions to Mandatory TDD

These categories don't require tests:

- CSS/asset-only changes (don't apply to vreader, but listed for completeness)
- Documentation, config, comments
- Type-only changes with no runtime effect
- Pure file moves / renames

If unsure, write the test.
