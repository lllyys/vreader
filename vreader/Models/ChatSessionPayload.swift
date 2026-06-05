// Purpose: The dedicated Codable persistence envelope for a ChatSession's
// message blob (Feature #88 WI-1, Gate-2 High 2). The live domain/UI types
// `ChatMessage` (ChatMessage.swift) and `ChatCitation` (ChatCitation.swift) are
// NOT Codable, so they are never serialized directly. Instead this file defines
// a stable Codable mirror (`PersistedChatMessage` / `PersistedChatCitation`)
// plus `ChatSessionPayloadMapper`, the pure map between blob ⇄ [ChatMessage].
// A top-level `version` field on the envelope rides along for forward-compat.
//
// Key decisions:
// - The two enums (`ChatRole`, `ChatCitation.SourceKind`) are persisted as their
//   String raw values; an unknown role on decode degrades to `.system` and an
//   unknown source kind to `.scope` rather than failing the whole blob.
// - `Locator` IS Codable (Locator.swift) and `ClosedRange<Int>` is Codable, so
//   the citation envelope encodes cleanly with no further mapping.
// - `decode` tolerates nil/empty/garbage data → [] (mirrors Highlight.anchor),
//   so a corrupted or legacy row never crashes the reader.
//
// @coordinates-with: ChatSession.swift, ChatMessage.swift,
//   Services/AI/ChatCitation.swift, Locator.swift

import Foundation

/// The versioned Codable envelope persisted in `ChatSession.messagesData`.
struct ChatSessionPayload: Codable {
    var version: Int
    var messages: [PersistedChatMessage]
}

/// Codable mirror of `ChatMessage`. `role` carries the `ChatRole` raw value.
struct PersistedChatMessage: Codable {
    var id: UUID
    var role: String
    var content: String
    var timestamp: Date
    var citations: [PersistedChatCitation]
}

/// Codable mirror of `ChatCitation` (fields per ChatCitation.swift:30-42).
struct PersistedChatCitation: Codable {
    var id: UUID
    var sourceKind: String
    var label: String
    var locator: Locator?
    var spanUTF16: ClosedRange<Int>?
    var sequence: Int?
    var aheadOfReader: Bool
}

/// Pure mapper between the live `[ChatMessage]` domain array and the persisted
/// `Data?` blob. The actor / model layer encode/decode through here; the domain
/// types are never serialized directly, so a domain-shape change can't corrupt
/// the stored blob.
enum ChatSessionPayloadMapper {

    /// The envelope version written by the current build.
    static let payloadVersion = 1

    // MARK: - Encode

    /// Encodes `messages` into the versioned blob, or **`nil` on encode failure**
    /// (Gate-4 Medium 1): callers must NOT overwrite a good stored blob with empty
    /// data on failure — the save layer (WI-2) skips the write when this is nil,
    /// preserving the prior blob. (Encoding finite Codable primitives won't
    /// realistically fail, but never silently wipe a conversation.)
    static func encode(_ messages: [ChatMessage]) -> Data? {
        let payload = ChatSessionPayload(
            version: payloadVersion,
            messages: messages.map(persist)
        )
        return try? JSONEncoder().encode(payload)
    }

    // MARK: - Decode

    static func decode(_ data: Data?) -> [ChatMessage] {
        guard let data, !data.isEmpty else { return [] }
        guard let payload = try? JSONDecoder().decode(ChatSessionPayload.self, from: data) else {
            return []
        }
        // Version gate (Gate-4 Medium 2): `payloadVersion` is now READ — only a
        // known version is interpreted. A FUTURE, potentially-incompatible version
        // (written by a newer build) returns [] here rather than silently
        // flattening unknown data; `isReadable(_:)` lets the WI-2 save layer detect
        // this and PRESERVE the stored blob instead of clobbering it.
        guard payload.version <= payloadVersion else { return [] }
        return payload.messages.map(domain)
    }

    /// Whether this build can interpret `data` (nil/empty, or a known payload
    /// version). The WI-2 save layer checks this before re-encoding a session, so
    /// a blob written by a future build is preserved, not overwritten.
    static func isReadable(_ data: Data?) -> Bool {
        guard let data, !data.isEmpty else { return true }
        guard let payload = try? JSONDecoder().decode(ChatSessionPayload.self, from: data) else {
            return true   // unparseable/garbage → treat as readable (decodes to []), not a future version to protect
        }
        return payload.version <= payloadVersion
    }

    // MARK: - Domain ⇄ Persisted

    private static func persist(_ message: ChatMessage) -> PersistedChatMessage {
        PersistedChatMessage(
            id: message.id,
            role: message.role.rawValue,
            content: message.content,
            timestamp: message.timestamp,
            citations: message.citations.map(persist)
        )
    }

    private static func domain(_ persisted: PersistedChatMessage) -> ChatMessage {
        ChatMessage(
            id: persisted.id,
            role: ChatRole(rawValue: persisted.role) ?? .system,
            content: persisted.content,
            timestamp: persisted.timestamp,
            citations: persisted.citations.map(domain)
        )
    }

    private static func persist(_ citation: ChatCitation) -> PersistedChatCitation {
        PersistedChatCitation(
            id: citation.id,
            sourceKind: citation.sourceKind.rawValue,
            label: citation.label,
            locator: citation.locator,
            spanUTF16: citation.spanUTF16,
            sequence: citation.sequence,
            aheadOfReader: citation.aheadOfReader
        )
    }

    private static func domain(_ persisted: PersistedChatCitation) -> ChatCitation {
        ChatCitation(
            id: persisted.id,
            sourceKind: ChatCitation.SourceKind(rawValue: persisted.sourceKind) ?? .scope,
            label: persisted.label,
            locator: persisted.locator,
            spanUTF16: persisted.spanUTF16,
            sequence: persisted.sequence,
            aheadOfReader: persisted.aheadOfReader
        )
    }
}
