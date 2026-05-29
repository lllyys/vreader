// Purpose: Pure decision logic for cross-chapter page advance in TXT paged
// mode (Bug #284 / GH #1261). TXT paged layout renders the CURRENT chapter as
// a sequence of pages via `NativeTextPageNavigator`; this type decides what a
// next/previous page-turn means when the reader sits at a chapter boundary.
//
// The grammar (design dev-docs/.../reader-navigation.md §2.2 — "tap = next
// page; chapter boundaries are nothing special"):
//   - Not on the boundary page  → advance/retreat within the current chapter.
//   - Last page + a next chapter → load chapter N+1, land on its first page.
//   - First page + a prev chapter → load chapter N-1, land on its last page.
//   - Document end / start       → clamp (bounce, no navigation).
//
// Extracted as a stand-alone pure type so the boundary arithmetic — including
// the empty/short-chapter edge cases — is unit-testable without standing up a
// SwiftUI view tree or a real paginator.
//
// @coordinates-with: TXTReaderContainerView.swift,
//   TXTReaderContainerView+Paged.swift, NativeTextPageNavigator.swift,
//   TXTReaderViewModel.swift

import Foundation

/// Pure cross-chapter advance decisions for TXT paged mode.
enum TXTPagedChapterAdvance {

    /// The decision a next/previous page-turn resolves to.
    enum Decision: Equatable {
        /// Turn stays inside the current chapter (delegate to the navigator).
        case withinChapter
        /// Load the next chapter and land on its first page.
        case crossToNextChapter
        /// Load the previous chapter and land on its last page.
        case crossToPreviousChapter
        /// Already at the last page of the last chapter — clamp (no nav).
        case clampAtDocumentEnd
        /// Already at the first page of the first chapter — clamp (no nav).
        case clampAtDocumentStart
    }

    /// Decide what a forward page-turn means.
    ///
    /// - Parameters:
    ///   - currentPage: 0-based page index within the current chapter.
    ///   - totalPages: page count of the current chapter (0 for an
    ///     empty/short chapter that paginated to nothing).
    ///   - hasNextChapter: whether a chapter after the current one exists.
    ///
    /// A chapter is on its last page when `currentPage >= totalPages - 1`.
    /// Empty chapters (`totalPages <= 0`) are treated as already on the
    /// boundary so the reader is never trapped.
    static func next(currentPage: Int, totalPages: Int, hasNextChapter: Bool) -> Decision {
        let lastPageIndex = max(totalPages - 1, 0)
        let onLastPage = currentPage >= lastPageIndex
        guard onLastPage else { return .withinChapter }
        return hasNextChapter ? .crossToNextChapter : .clampAtDocumentEnd
    }

    /// Decide what a backward page-turn means.
    ///
    /// On the first page (`currentPage <= 0`) the turn either crosses to the
    /// previous chapter's last page or clamps at the document start.
    static func previous(currentPage: Int, totalPages: Int, hasPreviousChapter: Bool) -> Decision {
        let onFirstPage = currentPage <= 0
        guard onFirstPage else { return .withinChapter }
        return hasPreviousChapter ? .crossToPreviousChapter : .clampAtDocumentStart
    }

    /// Page to land on after a forward cross-chapter load: always the first
    /// page of the freshly-loaded chapter.
    static func landingPageForwardCross(newTotalPages: Int) -> Int { 0 }

    /// Page to land on after a backward cross-chapter load: the last page of
    /// the freshly-loaded chapter (clamped to 0 for an empty chapter).
    static func landingPageBackwardCross(newTotalPages: Int) -> Int {
        max(newTotalPages - 1, 0)
    }
}

/// A queued cross-chapter landing: which page to land on once the TARGET
/// chapter has loaded and paginated. Lives alongside the pure decision logic
/// (no UIKit dependency) so the main container + paged extension can both
/// reference it.
///
/// Codex Gate-4 Round-1 (High #1 + #2): the landing carries its
/// `targetChapterIndex` so `repaginatePagedChapter` applies it ONLY when the
/// view model has actually loaded that chapter (`currentChapterIdx == target`).
/// This makes the queue self-healing against two failure modes:
///   - a `nextChapter()`/`previousChapter()` load that fails (the VM catches
///     the error, leaves the index unchanged) → the landing never matches the
///     current chapter, so it is never mis-applied to the old chapter on an
///     unrelated font/theme repaginate; the next legitimate cross overwrites it.
///   - a rapid second tap that advances past an intermediate chapter → the
///     intermediate chapter's rebuild does not match the (newer) target index,
///     so the landing is not consumed early.
struct TXTPagedLanding: Equatable {
    /// The chapter index this landing applies to (the freshly-targeted chapter).
    let targetChapterIndex: Int
    /// Which edge of the target chapter to land on.
    let edge: Edge

    enum Edge: Equatable {
        /// Forward cross — land on the target chapter's first page.
        case firstPage
        /// Backward cross — land on the target chapter's last page.
        case lastPage
    }
}
