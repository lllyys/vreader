// Purpose: Feature #85 WI-1 — a process-lifetime, @MainActor in-memory cache of
// the latest reading position per book, written SYNCHRONOUSLY by whichever EPUB
// host is active and read by the next host on open.
//
// Why: with approach C the SAME book uses two engines — Readium (paged) and the
// legacy #71 continuous-scroll stitch (scroll) — so a reading-mode toggle SWAPS
// hosts. Without a synchronous handoff the incoming host would restore a STALE
// persisted position before the outgoing host's async save-flush completed, then
// re-save it (Gate-4 round-1 High): concrete position LOSS in both directions.
// This cache is the freshest source of truth across a same-session host swap;
// persistence remains the across-launch source.
//
// The cached value is the engine-neutral `Locator` (href + progression) both
// hosts can produce — ReadiumEPUBHost maps its Readium locator to it via
// `makeVReaderLocator(...).legacyLocator` (the same mapping its dual-write
// uses); the legacy host already holds one. The href is whatever its writer
// used (container-relative from Readium, OPF-relative from the legacy parser);
// readers resolve it (EPUBScrollAnchorResolver for legacy, readiumLocator(from
// VReader:spineHrefs:) for Readium).
//
// @coordinates-with: ReadiumEPUBHost+Body.swift (record on locationDidChange,
//   read on open), EPUBReaderContainerView.swift (record on windowed-position,
//   read on open), ReaderContainerView.swift (the dispatcher that swaps hosts on
//   an `epubLayout` toggle).

import Foundation

/// In-memory, per-book latest reading position, handed off between EPUB hosts
/// across a same-session reading-mode (engine) swap.
@MainActor
final class ReaderPositionHandoff {
    static let shared = ReaderPositionHandoff()
    init() {}  // non-private so tests can construct an isolated instance

    private var latest: [String: Locator] = [:]

    /// Record the freshest engine-neutral position for a book. Called by the
    /// active host on every location change — synchronous on the main actor, so
    /// it never races the debounced async persistence save.
    func record(_ locator: Locator, forKey key: String) {
        guard !key.isEmpty else { return }
        latest[key] = locator
    }

    /// The freshest in-session position for a book, or nil if none was recorded
    /// this process lifetime. Does NOT clear on read — a re-open in the same
    /// mode should still see it; persistence is the durable across-launch
    /// fallback.
    func latestLocator(forKey key: String) -> Locator? {
        guard !key.isEmpty else { return nil }
        return latest[key]
    }
}
