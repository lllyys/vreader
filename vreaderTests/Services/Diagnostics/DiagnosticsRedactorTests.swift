// Purpose: Feature #96 WI-1 — the export-leak guard. Verifies DiagnosticsRedactor
// scrubs every known secret/credential/path shape while leaving benign content
// (identifiers, hashes, CJK) intact, and is idempotent.

import Testing
@testable import vreader

@Suite("DiagnosticsRedactor")
struct DiagnosticsRedactorTests {

    @Test func redactsBearerToken() {
        let out = DiagnosticsRedactor.redact("Authorization: Bearer sk-abc123def456ghi789jkl")
        #expect(!out.contains("sk-abc123def456ghi789jkl"))
        #expect(out.contains("Authorization: Bearer \(DiagnosticsRedactor.placeholder)"))
    }

    @Test func redactsBasicAuth() {
        let out = DiagnosticsRedactor.redact("Authorization: Basic YWxpY2U6aHVudGVyMg==")
        #expect(!out.contains("YWxpY2U6aHVudGVyMg=="))
    }

    @Test(arguments: [
        "apiKey=SUPERSECRETVALUE123",
        "access_token: aaaaaaaaaaaaaaaa",
        "refresh_token=rrrrrrrrrrrr",
        "password=hunter2hunter2",
        "client_secret: csXYZ987",
        "\"secret\": \"topsecretvalue\"",
    ])
    func redactsKeyedSecrets(_ input: String) {
        let out = DiagnosticsRedactor.redact("doing \(input) now")
        // The secret VALUE is gone; the placeholder is present.
        #expect(out.contains(DiagnosticsRedactor.placeholder))
        for leaked in ["SUPERSECRETVALUE123", "aaaaaaaaaaaaaaaa", "rrrrrrrrrrrr",
                       "hunter2hunter2", "csXYZ987", "topsecretvalue"] {
            #expect(!out.contains(leaked) || !input.contains(leaked))
        }
    }

    @Test func redactsOpenAIKey() {
        let out = DiagnosticsRedactor.redact("provider key sk-proj-AbCdEf1234567890XyZqrs failed")
        #expect(!out.contains("sk-proj-AbCdEf1234567890XyZqrs"))
    }

    @Test func redactsJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NSJ9.SflKxwRJSMeKKF2QT4f"
        let out = DiagnosticsRedactor.redact("session \(jwt) active")
        #expect(!out.contains(jwt))
    }

    @Test func redactsURLPasswordKeepsUser() {
        let out = DiagnosticsRedactor.redact("connecting https://alice:hunter2pw@dav.example.com/remote.php")
        #expect(!out.contains("hunter2pw"))
        #expect(out.contains("alice"))            // username kept
        #expect(out.contains("dav.example.com"))  // host kept
    }

    @Test(arguments: [
        "/Users/ll/Library/Application Support/x.epub",
        "/private/var/mobile/Containers/Data/Application/ABC/Documents/y.sqlite",
        "/var/mobile/Media/z.txt",
        "file:///Users/ll/Downloads/book.epub",
    ])
    func redactsFilePaths(_ path: String) {
        let out = DiagnosticsRedactor.redact("loaded \(path) ok")
        #expect(out.contains(DiagnosticsRedactor.pathPlaceholder))
        #expect(!out.contains("/Users/ll/Library"))
        #expect(!out.contains("Containers/Data/Application/ABC"))
    }

    // A keychain ACCOUNT LABEL is an identifier, not the secret — left intact.
    @Test func keepsKeychainAccountLabel() {
        let label = "com.vreader.ai.apiKey.ABCD-1234-EF"
        let out = DiagnosticsRedactor.redact("saved key to \(label)")
        #expect(out.contains(label))
    }

    // A bare content hash / fingerprint (no auth context) must NOT be blanket-redacted.
    @Test func doesNotBlanketRedactHashes() {
        let msg = "fingerprint epub:984f8611bb2842e0bc3a7b90cef7ffed37e4cc23:2956"
        #expect(DiagnosticsRedactor.redact(msg).contains("984f8611bb2842e0bc3a7b90cef7ffed37e4cc23"))
    }

    @Test func leavesCleanMessageUntouched() {
        let msg = "loaded 12 books in 0.34s"
        #expect(DiagnosticsRedactor.redact(msg) == msg)
    }

    @Test func preservesCJK() {
        let msg = "已加载 12 本书，用时 0.34 秒"
        #expect(DiagnosticsRedactor.redact(msg) == msg)
    }

    // Gate-4 High: a QUOTED secret value with whitespace must be fully redacted.
    @Test func redactsQuotedMultiWordSecret() {
        let out = DiagnosticsRedactor.redact(#"body {"password": "correct horse battery staple"}"#)
        #expect(!out.contains("correct horse battery staple"))
        #expect(!out.contains("horse battery"))
    }

    // Gate-4 High: serialized/JSON Authorization header shapes.
    @Test func redactsSerializedAuthorizationHeader() {
        let out = DiagnosticsRedactor.redact(#"headers {"Authorization": "Basic YWxpY2U6cHcxMjM="}"#)
        #expect(!out.contains("YWxpY2U6cHcxMjM="))
    }

    // Gate-4 Medium: a path with internal spaces must not leak its tail.
    @Test func redactsPathWithSpaces() {
        let out = DiagnosticsRedactor.redact(#"loaded /Users/ll/Library/Application Support/x.epub"#)
        #expect(!out.contains("Application Support"))
        #expect(!out.contains("x.epub"))
        #expect(out.contains(DiagnosticsRedactor.pathPlaceholder))
    }

    @Test func isIdempotent() {
        let msg = "Authorization: Bearer sk-abc123def456ghijk at /Users/ll/x.epub apiKey=ZZTOP123"
        let once = DiagnosticsRedactor.redact(msg)
        #expect(DiagnosticsRedactor.redact(once) == once)
    }
}
