// Purpose: Semantic state snapshot written by the vreader-debug://snapshot
// command (feature #44 DebugBridge). Stable JSON shape that automated tests
// and AI agents read back from the app container to assert on app state
// instead of pixels. DEBUG-only.

#if DEBUG

import Foundation

/// Semantic state of the app at the moment of snapshot. Encoded to JSON via
/// `DebugSnapshot.encoder` (sorted keys for deterministic output, explicit
/// `null` for missing values so consumers can distinguish "absent" from
/// "unknown").
///
/// Schema versioning: bump `schemaVersion` whenever fields are added,
/// removed, or change semantics. The `partial` array names fields whose
/// nil value means "not yet implemented in this build" rather than "no
/// value" — consumers should not treat partial-listed nil fields as
/// authoritative.
struct DebugSnapshot: Codable, Equatable {
    /// Schema version. Increment on field add/remove/semantics-change.
    /// **v2 (feature #49 WI-1)**: adds `ttsState`, `ttsOffsetUTF16`,
    /// `settingsProvenance`. Existing v1 fields unchanged.
    let schemaVersion: Int
    let ts: String
    let currentBookId: String?
    let format: String?
    let position: String?
    let theme: String?
    let fontSize: Int?
    let selection: SelectionInfo?
    let highlightCount: Int
    /// Render phase the active reader reports. Wire values are pinned to
    /// match `RenderPhaseValue` constants below — `idle` is the canonical
    /// "rendered + no in-flight work" state.
    let renderPhase: String
    let lastError: String?

    // MARK: - Schema v2 additions (feature #49 WI-1)

    /// Current TTS state ("idle" / "speaking" / "paused"). Nil if no TTS
    /// service has yet been wired into the snapshot capture context.
    let ttsState: String?

    /// Current TTS UTF-16 offset within the active book. Nil when not in a
    /// TTS-capable state, or when no service is wired. The deliberately
    /// limited surface (no sentence index) is documented in feature #49's
    /// plan as a phase-1 simplification.
    let ttsOffsetUTF16: Int?

    /// Whether the active reader's settings are sourced from per-book
    /// overrides ("perBook") or the global store ("global"). Nil when no
    /// reader is active or the provenance information isn't available.
    let settingsProvenance: String?

    /// Field names whose nil value in this snapshot means "not yet
    /// implemented" rather than "no value". Empty/nil array means every
    /// nil field is authoritative.
    let partial: [String]?

    /// Current schema version. Update with care — consumers may pin a
    /// version they recognize.
    static let currentSchemaVersion = 2

    /// Stable wire values for `renderPhase`. Tests + consumers pin against
    /// these constants instead of free-form strings.
    enum RenderPhaseValue {
        static let idle = "idle"
        static let loading = "loading"
        static let rendering = "rendering"
        static let settled = "settled"
    }

    /// Stable wire values for `ttsState`. Mirrors `TTSService.State`'s
    /// internal cases via the DEBUG-only `publicName` extension shipped
    /// alongside this WI.
    enum TTSStateValue {
        static let idle = "idle"
        static let speaking = "speaking"
        static let paused = "paused"
    }

    /// Stable wire values for `settingsProvenance`.
    enum SettingsProvenanceValue {
        static let global = "global"
        static let perBook = "perBook"
    }

    /// Selected text in the active reader, if any.
    struct SelectionInfo: Codable, Equatable {
        let text: String
        let startOffset: Int
        let endOffset: Int
    }

    /// Explicit init with v2 fields defaulted so existing call sites don't
    /// have to thread three new parameters through. New consumers (per-format
    /// hosts in feature #50) populate the v2 fields by name.
    init(
        schemaVersion: Int,
        ts: String,
        currentBookId: String?,
        format: String?,
        position: String?,
        theme: String?,
        fontSize: Int?,
        selection: SelectionInfo?,
        highlightCount: Int,
        renderPhase: String,
        lastError: String?,
        partial: [String]?,
        ttsState: String? = nil,
        ttsOffsetUTF16: Int? = nil,
        settingsProvenance: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.ts = ts
        self.currentBookId = currentBookId
        self.format = format
        self.position = position
        self.theme = theme
        self.fontSize = fontSize
        self.selection = selection
        self.highlightCount = highlightCount
        self.renderPhase = renderPhase
        self.lastError = lastError
        self.partial = partial
        self.ttsState = ttsState
        self.ttsOffsetUTF16 = ttsOffsetUTF16
        self.settingsProvenance = settingsProvenance
    }

    /// Decoder must accept v1 archives (which lack the v2 fields). Treat
    /// missing v2 fields as nil so the schema-bump is read-compatible —
    /// useful for tests that pin against a v1 fixture file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        self.ts = try c.decode(String.self, forKey: .ts)
        self.currentBookId = try c.decodeIfPresent(String.self, forKey: .currentBookId)
        self.format = try c.decodeIfPresent(String.self, forKey: .format)
        self.position = try c.decodeIfPresent(String.self, forKey: .position)
        self.theme = try c.decodeIfPresent(String.self, forKey: .theme)
        self.fontSize = try c.decodeIfPresent(Int.self, forKey: .fontSize)
        self.selection = try c.decodeIfPresent(SelectionInfo.self, forKey: .selection)
        self.highlightCount = try c.decode(Int.self, forKey: .highlightCount)
        self.renderPhase = try c.decode(String.self, forKey: .renderPhase)
        self.lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        self.partial = try c.decodeIfPresent([String].self, forKey: .partial)
        self.ttsState = try c.decodeIfPresent(String.self, forKey: .ttsState)
        self.ttsOffsetUTF16 = try c.decodeIfPresent(Int.self, forKey: .ttsOffsetUTF16)
        self.settingsProvenance = try c.decodeIfPresent(String.self, forKey: .settingsProvenance)
    }

    /// Encoder configured for stable, byte-comparable output.
    /// - Sorted keys (alphabetical) → deterministic across runs/machines.
    /// - Pretty-printed → human-readable when AI/agents inspect the file.
    /// Explicit `null` for nil optionals comes from the custom `encode(to:)`
    /// below — `JSONEncoder` would otherwise drop them silently.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()

    enum CodingKeys: String, CodingKey {
        case schemaVersion, ts, currentBookId, format, position, theme, fontSize
        case selection, highlightCount, renderPhase, lastError, partial
        case ttsState, ttsOffsetUTF16, settingsProvenance
    }

    /// Custom encoder: emits every field, writing `null` for nil optionals
    /// so consumers can distinguish "absent" from "unknown".
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(ts, forKey: .ts)
        try Self.encodeOptional(currentBookId, forKey: .currentBookId, in: &c)
        try Self.encodeOptional(format, forKey: .format, in: &c)
        try Self.encodeOptional(position, forKey: .position, in: &c)
        try Self.encodeOptional(theme, forKey: .theme, in: &c)
        try Self.encodeOptional(fontSize, forKey: .fontSize, in: &c)
        try Self.encodeOptional(selection, forKey: .selection, in: &c)
        try c.encode(highlightCount, forKey: .highlightCount)
        try c.encode(renderPhase, forKey: .renderPhase)
        try Self.encodeOptional(lastError, forKey: .lastError, in: &c)
        try Self.encodeOptional(partial, forKey: .partial, in: &c)
        // v2 fields (feature #49 WI-1)
        try Self.encodeOptional(ttsState, forKey: .ttsState, in: &c)
        try Self.encodeOptional(ttsOffsetUTF16, forKey: .ttsOffsetUTF16, in: &c)
        try Self.encodeOptional(settingsProvenance, forKey: .settingsProvenance, in: &c)
    }

    private static func encodeOptional<T: Encodable>(
        _ value: T?,
        forKey key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}

#endif
