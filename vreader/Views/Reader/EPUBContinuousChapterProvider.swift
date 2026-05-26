// Purpose: Feature #71 WI-6a — the testable factory that turns a spine index
// into a rewritten `EPUBChapterBody`, ready to be stitched into the
// continuous-scroll document. It is exactly the `chapterBodyProvider` closure
// the WI-4 `EPUBContinuousScrollCoordinator` is built with — extracted as a
// standalone type so the index→href→fetch→rewrite chain is unit-testable with a
// stub parser, decoupled from the live `EPUBReaderContainerView` wiring (WI-6b).
//
// Pipeline (per the plan's WI-6 surface area): spine index →
// `metadata.spineItems[i].href` → `parser.contentForSpineItem(href:)` →
// `EPUBChapterBodyRewriter.rewrite(...)` → `EPUBChapterBody`. Out-of-range
// indices throw (rather than crash) so a coordinator extend past the book edge
// is observable + the window does not advance (round-1 [H4] / [L2] defensive
// posture).
//
// @coordinates-with: EPUBContinuousScrollCoordinator.swift (chapterBodyProvider),
//   EPUBChapterBodyRewriter.swift, EPUBParserProtocol.swift, EPUBTypes.swift,
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-6a)

import Foundation

/// Builds an `EPUBChapterBody` for a spine index by fetching + rewriting the
/// chapter's XHTML. `@MainActor` to match the coordinator's
/// `chapterBodyProvider: @MainActor (Int) async throws -> EPUBChapterBody`
/// contract (it captures the View-layer rewrite inputs).
@MainActor
struct EPUBContinuousChapterProvider {
    /// The book's spine (reading order). The provider maps a spine *index* to
    /// `spineItems[index].href`.
    let spineItems: [EPUBSpineItem]
    /// The parser that yields a chapter's raw XHTML for an href.
    let parser: any EPUBParserProtocol
    /// Absolute `file://` (or foliate URL-scheme) prefix the rewriter rewrites
    /// relative resource URLs against (`EPUBChapterBodyRewriter.rewrite`).
    let resourceBaseAbsolutePrefix: String
    /// Loads a linked stylesheet's bytes by relative href (or nil to skip),
    /// forwarded to the rewriter's `linkedStylesheetLoader`.
    let linkedStylesheetLoader: (_ relativeHref: String) -> String?

    enum ProviderError: Error, Equatable {
        /// The requested spine index is outside `0..<spineItems.count`.
        case spineIndexOutOfRange(Int)
    }

    /// Fetch + rewrite the chapter at `spineIndex` into an `EPUBChapterBody`.
    /// Throws `spineIndexOutOfRange` for an index outside the spine (no parser
    /// fetch happens) so a coordinator extend past the book edge is a clean
    /// no-op rather than a crash.
    func body(spineIndex: Int) async throws -> EPUBChapterBody {
        guard spineIndex >= 0, spineIndex < spineItems.count else {
            throw ProviderError.spineIndexOutOfRange(spineIndex)
        }
        let href = spineItems[spineIndex].href
        let xhtml = try await parser.contentForSpineItem(href: href)
        return EPUBChapterBodyRewriter.rewrite(
            xhtml: xhtml,
            spineIndex: spineIndex,
            href: href,
            resourceBaseAbsolutePrefix: resourceBaseAbsolutePrefix,
            linkedStylesheetLoader: linkedStylesheetLoader
        )
    }

    /// The provider as the bare closure the coordinator's `chapterBodyProvider`
    /// parameter expects — `WI-6b` passes `provider.makeClosure()` straight in.
    func makeClosure() -> @MainActor (Int) async throws -> EPUBChapterBody {
        { spineIndex in try await body(spineIndex: spineIndex) }
    }
}
