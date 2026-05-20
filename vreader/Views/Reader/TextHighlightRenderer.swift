// Purpose: HighlightRenderer adapter for TXT and MD formats (Phase R4a).
// Translates highlight operations into TextReaderUIState mutations.
// The bridge (TXTTextViewBridge / TXTChunkedReaderBridge) reads the state
// and renders highlights as NSAttributedString background colors.
//
// Key decisions:
// - Wraps existing TextReaderUIState logic — no new rendering mechanism.
// - apply() sets both the active highlight (for flash feedback) and persisted ranges.
// - remove() only clears the active highlight; restore() rebuilds the full list.
// - Shared between TXT and MD because both use the same UITextView-based bridge.
//
// @coordinates-with: TextReaderUIState.swift, HighlightRenderer.swift,
//   HighlightCoordinator.swift, TXTReaderContainerView.swift, MDReaderContainerView.swift

#if canImport(UIKit)
import Foundation

/// Highlight renderer for TXT and MD formats.
/// Mutates `TextReaderUIState` to drive visual highlight display.
@MainActor
final class TextHighlightRenderer: HighlightRenderer {
    let uiState: TextReaderUIState

    init(uiState: TextReaderUIState) {
        self.uiState = uiState
    }

    func apply(record: HighlightRecord) {
        guard let start = record.locator.charRangeStartUTF16,
              let end = record.locator.charRangeEndUTF16,
              end > start else { return }
        let range = NSRange(location: start, length: end - start)
        uiState.highlightIsTemporary = false
        uiState.highlightRange = range
        // Bug #237 round-2 audit (Medium): make `apply` idempotent on
        // highlightId. Two rapid `HighlightCoordinator.create(...)` calls
        // with the same locator dedupe to ONE persistence row (the
        // `profileKey + anchor` match in `PersistenceActor.addHighlight`),
        // but both still hit `renderer.apply(record:)` — pre-fix that
        // double-appended the range, double-rendering the highlight in
        // the current session until the next full restore.
        // Gesture path was protected by physical input rate limiting;
        // the DebugBridge highlight-driver (vreader-debug://highlight)
        // can fire URLs back-to-back, so the latent bug becomes
        // observable. Skip the append when the id is already tracked.
        if uiState.persistedHighlightLookup.contains(where: { $0.id == record.highlightId }) {
            return
        }
        // Bug #208 / GH #776: carry the record's stored color through to
        // the painter instead of dropping it (which forced a yellow paint).
        uiState.persistedHighlightRanges.append(
            PaintedHighlight(range: range, colorName: record.color)
        )
        // Feature #53 WI-2/WI-2b: keep the UUID-keyed lookup in sync with
        // newly-created highlights so the tap-on-highlight hit-test can
        // resolve a fresh paint. Pre-WI-2b, only the range array was
        // appended here; the lookup was only refreshed on full re-fetch
        // (e.g., after delete), leaving the just-created highlight
        // invisible to the hit-tester until the next reopen.
        uiState.persistedHighlightLookup.append(PersistedHighlightLookupEntry(
            id: record.highlightId,
            range: range
        ))
    }

    func remove(id: UUID) {
        uiState.highlightRange = nil
    }

    func restore(
        records: [HighlightRecord],
        forHref href: String?,
        using evaluator: ((String) -> Void)?
    ) {
        // TextHighlightRenderer doesn't filter by chapter and doesn't
        // go through a JS evaluator — it mutates UIKit state directly.
        // Both parameters are EPUB-specific; ignored here.
        _ = (href, evaluator)
        uiState.refreshPersistedHighlights(from: records)
    }
}
#endif
