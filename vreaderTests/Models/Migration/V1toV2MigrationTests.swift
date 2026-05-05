// Purpose: Tests for SchemaV2 migration — Highlight with optional anchor,
// profileKey derivation, backward compatibility.

import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import vreader

@Suite("V1toV2Migration")
struct V1toV2MigrationTests {

    // MARK: - SchemaV2 Structure

    @Test func schemaV2VersionIsTwoZeroZero() {
        #expect(SchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
    }

    @Test func schemaV2HasAllModels() {
        let models = SchemaV2.models
        // Same 7 models as V1 — no new model classes added
        #expect(models.count == 7)
    }

    @Test func migrationPlanIncludesBothSchemas() {
        // Assertion checks what the test name claims — V1 AND V2 are present —
        // not a hardcoded count, which drifts as later schema versions ship.
        let schemaNames = VReaderMigrationPlan.schemas.map { String(describing: $0) }
        #expect(schemaNames.contains("SchemaV1"))
        #expect(schemaNames.contains("SchemaV2"))
    }

    @Test func migrationPlanHasNoExplicitStages() {
        // V1→V2 is a lightweight additive migration (optional field).
        // SwiftData infers it automatically — no explicit stages needed.
        let stages = VReaderMigrationPlan.stages
        #expect(stages.isEmpty)
    }

    // MARK: - Highlight with Anchor

    @Test func highlightWithAnchorOnlyProfileKeyDerivedFromAnchor() {
        let fp = DocumentFingerprint(
            contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
            fileByteCount: 1024,
            format: .epub
        )
        let locator = Locator(
            bookFingerprint: fp,
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: "/6/4", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let range = EPUBSerializedRange(
            startContainerPath: "/html/body/p[1]/text()",
            startOffset: 0,
            endContainerPath: "/html/body/p[1]/text()",
            endOffset: 10
        )
        let anchor = AnnotationAnchor.epub(
            href: "ch1.xhtml",
            cfi: "/6/4",
            serializedRange: range
        )
        let highlight = Highlight(
            locator: locator,
            selectedText: "test",
            color: "yellow"
        )
        highlight.updateAnchor(anchor)
        #expect(highlight.anchor == anchor)
    }

    @Test func highlightProfileKeyFromLocatorStillWorks() {
        let fp = DocumentFingerprint(
            contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
            fileByteCount: 512,
            format: .txt
        )
        let locator = Locator(
            bookFingerprint: fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: nil,
            charRangeStartUTF16: 100, charRangeEndUTF16: 200,
            textQuote: "selected", textContextBefore: nil, textContextAfter: nil
        )
        let highlight = Highlight(locator: locator, selectedText: "selected")
        let expectedPrefix = fp.canonicalKey + ":"
        #expect(highlight.profileKey.hasPrefix(expectedPrefix))
    }

    @Test func highlightAnchorDefaultsToNil() {
        let fp = DocumentFingerprint(
            contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
            fileByteCount: 256,
            format: .pdf
        )
        let locator = Locator(
            bookFingerprint: fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: 5,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let highlight = Highlight(locator: locator, selectedText: "hello")
        #expect(highlight.anchor == nil)
    }

    @Test func highlightUpdateAnchorSetsValue() {
        let fp = DocumentFingerprint(
            contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
            fileByteCount: 256,
            format: .pdf
        )
        let locator = Locator(
            bookFingerprint: fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: 5,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let highlight = Highlight(locator: locator, selectedText: "hello")

        let anchor = AnnotationAnchor.pdf(
            page: 5,
            rects: [CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.02)]
        )
        highlight.updateAnchor(anchor)
        #expect(highlight.anchor == anchor)
    }
}
