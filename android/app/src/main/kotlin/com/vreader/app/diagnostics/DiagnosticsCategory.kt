package com.vreader.app.diagnostics

/**
 * Purpose: Feature #164 WI-3 — the subsystem vocabulary vreader's own log entries carry.
 *
 * The set is NOT ours to choose: it is the design's category chip row verbatim
 * (`DIAG_CATEGORIES` in `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`,
 * minus the constant leading `All` chip). Inventing a category here would put a chip on a
 * designed surface that the design does not depict (rule 51).
 *
 * Why an enum at all, rather than reusing logcat tags: logcat tags are arbitrary per-file strings
 * (`"ReaderActivity"`, `"FoliateBridge"`, `"BookShare"`, `"SearchIndexCoordinator"`), so four of
 * this app's six log sites would have landed in four unrelated chips. `VLog` + this enum is what
 * gives our entries a stable vocabulary; the original class name is not lost — it moves into the
 * message body as a `[ClassName]` prefix.
 *
 * Android-only concerns map ONTO this set rather than extending it:
 * search indexing -> [LIBRARY], Room/DAO -> [PERSISTENCE], share/export -> [LIBRARY].
 *
 * @coordinates-with VLog.kt, DiagnosticsCategoryBounding.kt
 */
enum class DiagnosticsCategory(val tag: String) {
    LIBRARY("Library"),
    PERSISTENCE("Persistence"),
    READER("Reader"),
    AI("AI"),
    SYNC("Sync"),
    DEBUG_BRIDGE("DebugBridge"),
}
