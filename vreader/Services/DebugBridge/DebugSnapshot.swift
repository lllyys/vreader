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
    let schemaVersion: Int
    let ts: String
    let currentBookId: String?
    let format: String?
    let position: String?
    let theme: String?
    let fontSize: Int?
    let selection: SelectionInfo?
    let highlightCount: Int
    let renderPhase: String
    let lastError: String?
    /// Field names whose nil value in this snapshot means "not yet
    /// implemented" rather than "no value". Empty/nil array means every
    /// nil field is authoritative.
    let partial: [String]?

    /// Current schema version. Update with care — consumers may pin a
    /// version they recognize.
    static let currentSchemaVersion = 1

    /// Selected text in the active reader, if any.
    struct SelectionInfo: Codable, Equatable {
        let text: String
        let startOffset: Int
        let endOffset: Int
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
