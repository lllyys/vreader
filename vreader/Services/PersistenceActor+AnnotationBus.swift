// Purpose: The single mutation-complete signal for the reader's own annotations.
// Feature #86 WI-2 posts `.readerAnnotationsDidChange` from the PersistenceActor
// mutation chokepoints (highlight / bookmark / standalone-annotation add·remove·
// update + import) AFTER a successful SwiftData save, so the AI Chat
// `ChatAnnotationCache` can refresh without polling SwiftData on every relocate.
//
// Why the actor is the right place (Gate-2 r3): enumerating UI callers misses
// reader-side direct mutation paths (ReaderNotificationHandlers, the EPUB/PDF/
// Foliate containers, HighlightCoordinator, FoliateHighlightMutator). Posting from
// the actor methods covers every caller by construction (rule 50: all SwiftData
// mutations go through PersistenceActor).
//
// @coordinates-with: PersistenceActor+Highlights.swift,
//   PersistenceActor+Bookmarks.swift, PersistenceActor+Annotations.swift,
//   ReaderNotifications.swift, ChatAnnotationCache.swift (WI-4)

import Foundation

extension PersistenceActor {
    /// Posts `.readerAnnotationsDidChange` after a successful annotation mutation.
    /// `NotificationCenter.post` is thread-safe; observers register on `.main`, so
    /// the actor never blocks on observer work. Called only after a real `save()`
    /// (never on an idempotent no-op or a dedupe-return where nothing changed).
    nonisolated func postAnnotationsDidChange() {
        NotificationCenter.default.post(name: .readerAnnotationsDidChange, object: nil)
    }
}
