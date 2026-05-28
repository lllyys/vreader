// Purpose: Durable, engine-agnostic reading-position envelope (Feature #42).
// Wraps an engine's locator representation behind a vreader-owned value type so
// saved positions survive an engine swap / re-conversion. Never persist a raw
// engine-internal anchor — persist this envelope instead.
//
// Key decisions:
// - Value type (Codable/Equatable/Sendable), NOT a @Model. Stored on
//   ReadingPosition as raw `Data?` (SchemaV8), mirroring Highlight.anchorData's
//   SwiftData-safe precedent — a Codable struct decoded with try? rather than a
//   @Model column SwiftData would have to materialize.
// - `engine` disambiguates which locator representation is authoritative during
//   the two-engine era: `.epubWKWebView` (legacy `Locator`) vs `.readium`
//   (`readiumLocatorJSON`, Readium's Locator serialized as plain JSON — so this
//   type needs NO Readium dependency).
// - `legacyLocator` carries the existing per-format `Locator` for back-compat /
//   dual-write, so both engines persist through one envelope.
// - `canonicalHash` mirrors Locator.canonicalHash / AnnotationAnchor.anchorHash:
//   sorted-keys JSON, SHA-256, hex string. Deterministic + stable across
//   encode/decode round-trips for dedup/sync keys.
//
// @coordinates-with: Locator.swift, ReadingPosition.swift, SchemaV8.swift

import Foundation
import CryptoKit

/// Which reader engine produced the authoritative locator in a VReaderLocator.
enum ReaderLocatorEngine: String, Codable, Hashable, Sendable, CaseIterable {
    /// The legacy bespoke EPUBWebViewBridge engine — locator lives in `legacyLocator`.
    case epubWKWebView
    /// The Readium Swift Toolkit engine — locator lives in `readiumLocatorJSON`.
    case readium
}

/// Durable engine-agnostic position envelope. Wraps an engine locator + survives
/// re-conversion. Persisted as JSON-encoded `Data?` on `ReadingPosition`.
struct VReaderLocator: Codable, Equatable, Sendable {
    /// The book's `DocumentFingerprint.canonicalKey`.
    let fingerprintKey: String

    /// The book's original (imported) format.
    let originalFormat: BookFormat

    /// Which engine's locator is authoritative.
    let engine: ReaderLocatorEngine

    /// Readium's `Locator` serialized as JSON (stored as a plain String so this
    /// type carries no Readium dependency). nil for the legacy engine.
    let readiumLocatorJSON: String?

    /// The existing per-format vreader `Locator`, for back-compat / dual-write.
    /// nil when only a Readium locator is available.
    let legacyLocator: Locator?

    /// Envelope schema version (lets future fields evolve independently of the
    /// SwiftData schema version).
    let schemaVersion: Int

    // MARK: - Init

    init(
        fingerprintKey: String,
        originalFormat: BookFormat,
        engine: ReaderLocatorEngine,
        readiumLocatorJSON: String?,
        legacyLocator: Locator?,
        schemaVersion: Int = VReaderLocator.currentSchemaVersion
    ) {
        self.fingerprintKey = fingerprintKey
        self.originalFormat = originalFormat
        self.engine = engine
        self.readiumLocatorJSON = readiumLocatorJSON
        self.legacyLocator = legacyLocator
        self.schemaVersion = schemaVersion
    }

    /// Current envelope schema version.
    static let currentSchemaVersion = 1

    // MARK: - Legacy wrapping

    /// Wraps an existing `Locator` as a legacy-engine envelope. Derives
    /// `fingerprintKey` and `originalFormat` from the locator's fingerprint, so
    /// both engines persist through one model.
    init(legacyLocator: Locator, schemaVersion: Int = VReaderLocator.currentSchemaVersion) {
        self.fingerprintKey = legacyLocator.bookFingerprint.canonicalKey
        self.originalFormat = legacyLocator.bookFingerprint.format
        self.engine = .epubWKWebView
        self.readiumLocatorJSON = nil
        self.legacyLocator = legacyLocator
        self.schemaVersion = schemaVersion
    }

    // MARK: - Canonical Hash

    /// SHA-256 hash of the canonical (sorted-keys) JSON encoding. Deterministic
    /// and stable across encode/decode round-trips. Used for dedup/sync keys.
    var canonicalHash: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // VReaderLocator is always encodable (all fields are Codable value types).
        let data = (try? encoder.encode(self)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
