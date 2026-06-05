// Purpose: Tests for ChatSessionPayloadMapper — the pure mapper between the live
// domain types ([ChatMessage] / ChatCitation, which are NOT Codable) and the
// dedicated Codable persistence envelope (ChatSessionPayload /
// PersistedChatMessage / PersistedChatCitation). Covers round-trips incl. CJK,
// every ChatRole, citations (all fields), and the nil/empty/garbage-data → []
// degradation cases. Feature #88 WI-1.
//
// @coordinates-with: ChatSessionPayload.swift, ChatMessage.swift, ChatCitation.swift

import Testing
import Foundation
@testable import vreader

@Suite("ChatSessionPayload")
struct ChatSessionPayloadTests {

    // MARK: - Helpers

    private static let fp = DocumentFingerprint(
        contentSHA256: String(repeating: "a", count: 64),
        fileByteCount: 1024,
        format: .epub
    )

    private static func locator() -> Locator {
        Locator(
            bookFingerprint: fp, href: "ch1.xhtml",
            progression: 0.25, totalProgression: 0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 120, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - Empty round-trip

    @Test func emptyMessagesRoundTrip() {
        let data = ChatSessionPayloadMapper.encode([])
        let decoded = ChatSessionPayloadMapper.decode(data)
        #expect(decoded.isEmpty)
    }

    // MARK: - Multiple roles round-trip

    @Test func multipleRolesRoundTrip() {
        let messages = [
            ChatMessage(role: .system, content: "You are a helpful reading companion."),
            ChatMessage(role: .user, content: "Who is the protagonist?"),
            ChatMessage(role: .assistant, content: "The protagonist is Ishmael."),
        ]
        let decoded = ChatSessionPayloadMapper.decode(ChatSessionPayloadMapper.encode(messages))
        #expect(decoded == messages)
        #expect(decoded.map(\.role) == [.system, .user, .assistant])
    }

    // MARK: - CJK content round-trip

    @Test func cjkContentRoundTrips() {
        let messages = [
            ChatMessage(role: .user, content: "这本书的主题是什么？"),
            ChatMessage(role: .assistant, content: "主题是孤独与海洋。日本語のテストも含む。"),
        ]
        let decoded = ChatSessionPayloadMapper.decode(ChatSessionPayloadMapper.encode(messages))
        #expect(decoded == messages)
        #expect(decoded[0].content == "这本书的主题是什么？")
    }

    // MARK: - Message WITH citations (every citation field)

    @Test func messageWithFullCitationsRoundTrips() {
        let citation = ChatCitation(
            sourceKind: .wholeBookSpan,
            label: "Ch. 3",
            locator: Self.locator(),
            spanUTF16: 100...250,
            sequence: 3,
            aheadOfReader: true
        )
        let messages = [
            ChatMessage(role: .user, content: "Summarize chapter 3."),
            ChatMessage(
                role: .assistant,
                content: "Chapter 3 covers the voyage.",
                citations: [citation]
            ),
        ]
        let decoded = ChatSessionPayloadMapper.decode(ChatSessionPayloadMapper.encode(messages))
        #expect(decoded == messages)

        let roundTripped = try? #require(decoded.last?.citations.first)
        #expect(roundTripped?.sourceKind == .wholeBookSpan)
        #expect(roundTripped?.label == "Ch. 3")
        #expect(roundTripped?.locator == Self.locator())
        #expect(roundTripped?.spanUTF16 == 100...250)
        #expect(roundTripped?.sequence == 3)
        #expect(roundTripped?.aheadOfReader == true)
    }

    // MARK: - Citation with nil optionals + every SourceKind

    @Test func citationOptionalsAndKindsRoundTrip() {
        let kinds: [ChatCitation.SourceKind] = [.scope, .note, .highlight, .bookmark, .wholeBookSpan]
        let citations = kinds.map { kind in
            ChatCitation(
                sourceKind: kind,
                label: "label-\(kind.rawValue)",
                locator: nil,
                spanUTF16: nil,
                sequence: nil,
                aheadOfReader: false
            )
        }
        let messages = [ChatMessage(role: .assistant, content: "Drew on several sources.", citations: citations)]
        let decoded = ChatSessionPayloadMapper.decode(ChatSessionPayloadMapper.encode(messages))
        #expect(decoded == messages)
        #expect(decoded.first?.citations.map(\.sourceKind) == kinds)
        #expect(decoded.first?.citations.allSatisfy { $0.locator == nil && $0.spanUTF16 == nil && $0.sequence == nil } == true)
    }

    // MARK: - Mixed citation presence across messages

    @Test func mixedCitationPresenceRoundTrips() {
        let messages = [
            ChatMessage(role: .user, content: "Q1"),
            ChatMessage(role: .assistant, content: "A1", citations: []),
            ChatMessage(
                role: .assistant,
                content: "A2",
                citations: [ChatCitation(sourceKind: .scope, label: "Section")]
            ),
        ]
        let decoded = ChatSessionPayloadMapper.decode(ChatSessionPayloadMapper.encode(messages))
        #expect(decoded == messages)
    }

    // MARK: - Degradation: nil / empty / garbage data → []

    @Test func nilDataDecodesToEmpty() {
        #expect(ChatSessionPayloadMapper.decode(nil).isEmpty)
    }

    @Test func emptyDataDecodesToEmpty() {
        #expect(ChatSessionPayloadMapper.decode(Data()).isEmpty)
    }

    @Test func garbageDataDecodesToEmpty() {
        let garbage = Data([0x00, 0x01, 0xFF, 0xFE, 0x42])
        #expect(ChatSessionPayloadMapper.decode(garbage).isEmpty)
    }

    @Test func wrongShapeJSONDecodesToEmpty() {
        let wrong = Data(#"{"foo":"bar","baz":[1,2,3]}"#.utf8)
        #expect(ChatSessionPayloadMapper.decode(wrong).isEmpty)
    }

    // MARK: - Gate-4 Medium 1: encode never wipes (returns nil, not empty Data)

    @Test func encodeReturnsNonNilForValidMessages() {
        let data = ChatSessionPayloadMapper.encode([ChatMessage(role: .user, content: "hi")])
        #expect(data != nil)
        #expect(data?.isEmpty == false)
    }

    // MARK: - Gate-4 Medium 2: payloadVersion is READ (forward-compat gate)

    @Test func futureVersionDecodesToEmpty_notSilentlyFlattened() {
        // A blob written by a hypothetical NEWER build (version 999). This build
        // must not silently interpret it — decode returns [] (and isReadable is
        // false so the WI-2 save layer preserves it).
        let future = Data(#"{"version":999,"messages":[{"id":"00000000-0000-0000-0000-000000000001","role":"user","content":"future","timestamp":0,"citations":[]}]}"#.utf8)
        #expect(ChatSessionPayloadMapper.decode(future).isEmpty)
        #expect(ChatSessionPayloadMapper.isReadable(future) == false)
    }

    @Test func currentVersionIsReadable_andRoundTrips() {
        let data = ChatSessionPayloadMapper.encode([ChatMessage(role: .assistant, content: "v1")])
        #expect(ChatSessionPayloadMapper.isReadable(data) == true)
        #expect(ChatSessionPayloadMapper.decode(data).first?.content == "v1")
    }

    @Test func nilAndGarbageAreReadable() {
        #expect(ChatSessionPayloadMapper.isReadable(nil) == true)
        #expect(ChatSessionPayloadMapper.isReadable(Data([0xFF, 0x00])) == true)
    }
}
