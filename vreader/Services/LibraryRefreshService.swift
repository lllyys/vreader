// Purpose: Service for library refresh operations — file existence verification
// and refresh throttling. Does NOT rescan file bytes (Section 9.1).
//
// Key decisions:
// - Refresh verifies file existence + updates lightweight timestamps only.
// - Full metadata re-parse is a separate manual "Rebuild Metadata" action.
// - Throttled: minimum 5s between refreshes (configurable for tests).
// - FileExistenceChecking protocol enables mock injection for tests.
// - Uses @unchecked Sendable with NSLock for mutable throttle state.
//   This is safe because: (1) the class is final, (2) all mutable state (_lastRefreshTime)
//   is guarded by the same lock, (3) the lock scope is minimal (no await inside lock).

import Foundation

/// Protocol for file existence checking, enabling mock injection in tests.
protocol FileExistenceChecking: Sendable {
    func fileExists(atPath path: String) -> Bool
}

/// Default implementation using FileManager.
struct DefaultFileExistenceChecker: FileExistenceChecking {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// Service for library refresh operations.
final class LibraryRefreshService: @unchecked Sendable {

    /// Information needed to verify a book's file existence.
    struct BookFileInfo: Sendable {
        let fingerprintKey: String
        let sandboxFilePath: String?
    }

    /// Result of file existence verification.
    struct VerificationResult: Sendable {
        let existing: [BookFileInfo]
        let missing: [BookFileInfo]
    }

    private let fileChecker: any FileExistenceChecking
    private let throttleInterval: TimeInterval
    private let lock = NSLock()
    private var _lastRefreshTime: Date?

    init(
        fileChecker: any FileExistenceChecking = DefaultFileExistenceChecker(),
        throttleInterval: TimeInterval = 5.0
    ) {
        self.fileChecker = fileChecker
        self.throttleInterval = throttleInterval
    }

    // MARK: - File Existence

    /// Verifies file existence for the given books.
    /// Returns which books' files still exist and which are missing.
    func verifyFileExistence(books: [BookFileInfo]) -> VerificationResult {
        var existing: [BookFileInfo] = []
        var missing: [BookFileInfo] = []

        for book in books {
            guard let path = book.sandboxFilePath else {
                missing.append(book)
                continue
            }
            if fileChecker.fileExists(atPath: path) {
                existing.append(book)
            } else {
                missing.append(book)
            }
        }

        return VerificationResult(existing: existing, missing: missing)
    }

    // MARK: - Throttling

    /// Atomically checks whether a refresh is allowed and, if so, records the
    /// current time as the last refresh. Returns true if the refresh may proceed.
    /// This combines the previous shouldAllowRefresh() + recordRefresh() into a
    /// single lock acquisition to prevent concurrent callers from both passing
    /// the throttle check.
    func tryAcquireRefreshPermit() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if let last = _lastRefreshTime,
           Date().timeIntervalSince(last) < throttleInterval {
            return false
        }
        _lastRefreshTime = Date()
        return true
    }

    /// Whether a refresh should be allowed based on throttle interval.
    /// - Important: Use `tryAcquireRefreshPermit()` instead for atomic check-and-record.
    @available(*, deprecated, message: "Use tryAcquireRefreshPermit() for atomic check-and-record")
    func shouldAllowRefresh() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let last = _lastRefreshTime else { return true }
        return Date().timeIntervalSince(last) >= throttleInterval
    }

    /// Records that a refresh just occurred.
    /// - Important: Use `tryAcquireRefreshPermit()` instead for atomic check-and-record.
    @available(*, deprecated, message: "Use tryAcquireRefreshPermit() for atomic check-and-record")
    func recordRefresh() {
        lock.lock()
        defer { lock.unlock() }
        _lastRefreshTime = Date()
    }
}
