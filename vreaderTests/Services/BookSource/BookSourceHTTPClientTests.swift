// Purpose: Tests for BookSourceHTTPClient — HTTP fetching, encoding detection,
// custom headers, rate limiting, error handling.
//
// Uses a mock URLProtocol to intercept network requests without real HTTP.
//
// @coordinates-with: BookSourceHTTPClient.swift, WebPageEncodingDetector.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Mock URLProtocol

/// Intercepts URLSession requests for testing without real network access.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    /// Guards the process-global mock state below. `URLProtocol`
    /// instances run on the URL loading system's own threads, and
    /// `fetchPage_concurrent_safe` drives several requests at once,
    /// so every access to the shared handler / capture log must be
    /// synchronized (Bug #213 / GH #830).
    private static let lock = NSLock()

    nonisolated(unsafe) private static var _requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) private static var _capturedRequests: [URLRequest] = []

    /// Handler to provide mock responses. Set before each test.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return _requestHandler }
        set { lock.lock(); defer { lock.unlock() }; _requestHandler = newValue }
    }

    /// Captured requests for verification.
    static var capturedRequests: [URLRequest] {
        get { lock.lock(); defer { lock.unlock() }; return _capturedRequests }
        set { lock.lock(); defer { lock.unlock() }; _capturedRequests = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Snapshot the handler and record the request under one lock
        // acquisition; release before invoking the handler / client
        // callbacks so slow work never runs while holding the lock.
        Self.lock.lock()
        Self._capturedRequests.append(request)
        let handler = Self._requestHandler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helper

/// Creates a URLSession using MockURLProtocol.
private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

/// Creates a mock HTTP response.
private func mockResponse(
    url: URL,
    statusCode: Int = 200,
    contentType: String? = "text/html; charset=utf-8"
) -> HTTPURLResponse {
    var headers: [String: String] = [:]
    if let ct = contentType {
        headers["Content-Type"] = ct
    }
    return HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}

// MARK: - Tests

// Bug #213 / GH #830: `.serialized` is mandatory here. `MockURLProtocol`
// holds the mock handler and captured-request log in process-global
// `static` storage; Swift Testing runs a suite's `@Test`s in parallel
// by default, so without serialization a concurrent test's `init()`
// (below) wipes another test's handler mid-flight — tests then receive
// each other's mocked responses and see each other's captured requests,
// failing non-deterministically. `.serialized` runs these tests one at
// a time, which makes the per-test `init()` reset sound.
@Suite("BookSourceHTTPClient", .serialized)
struct BookSourceHTTPClientTests {

    init() {
        MockURLProtocol.capturedRequests = []
        MockURLProtocol.requestHandler = nil
    }

    // MARK: - fetchPage Success

    @Test func fetchPage_success_returnsHTML() async throws {
        let testURL = URL(string: "https://example.com/page")!
        let html = "<html><body>Hello World</body></html>"

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL), html.data(using: .utf8)!)
        }

        let client = BookSourceHTTPClient(session: makeMockSession())
        let result = try await client.fetchPage(url: testURL)

        #expect(result.contains("Hello World"))
    }

    // MARK: - HTTP Error Codes

    @Test func fetchPage_404_returnsError() async {
        let testURL = URL(string: "https://example.com/missing")!

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL, statusCode: 404), Data())
        }

        let client = BookSourceHTTPClient(session: makeMockSession())

        do {
            _ = try await client.fetchPage(url: testURL)
            Issue.record("Expected HTTPClientError.httpError")
        } catch let error as HTTPClientError {
            if case .httpError(let code) = error {
                #expect(code == 404)
            } else {
                Issue.record("Expected .httpError(404), got \(error)")
            }
        } catch {
            Issue.record("Expected HTTPClientError, got \(error)")
        }
    }

    @Test func fetchPage_500_returnsError() async {
        let testURL = URL(string: "https://example.com/error")!

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL, statusCode: 500), Data())
        }

        let client = BookSourceHTTPClient(session: makeMockSession())

        do {
            _ = try await client.fetchPage(url: testURL)
            Issue.record("Expected HTTPClientError.httpError")
        } catch let error as HTTPClientError {
            if case .httpError(let code) = error {
                #expect(code == 500)
            } else {
                Issue.record("Expected .httpError(500), got \(error)")
            }
        } catch {
            Issue.record("Expected HTTPClientError, got \(error)")
        }
    }

    // MARK: - Timeout

    @Test func fetchPage_timeout_returnsError() async {
        let testURL = URL(string: "https://example.com/slow")!

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let client = BookSourceHTTPClient(session: makeMockSession())

        do {
            _ = try await client.fetchPage(url: testURL)
            Issue.record("Expected HTTPClientError.networkError")
        } catch let error as HTTPClientError {
            if case .networkError = error {
                // expected
            } else {
                Issue.record("Expected .networkError, got \(error)")
            }
        } catch {
            Issue.record("Expected HTTPClientError, got \(error)")
        }
    }

    // MARK: - Custom Headers

    @Test func fetchPage_customHeaders_included() async throws {
        let testURL = URL(string: "https://example.com/page")!
        let html = "<html><body>OK</body></html>"

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL), html.data(using: .utf8)!)
        }

        let customHeaders = [
            "User-Agent": "VReader/1.0",
            "Referer": "https://example.com",
            "X-Custom": "test-value"
        ]

        let client = BookSourceHTTPClient(session: makeMockSession())
        _ = try await client.fetchPage(url: testURL, headers: customHeaders)

        #expect(MockURLProtocol.capturedRequests.count == 1)
        let captured = MockURLProtocol.capturedRequests[0]
        #expect(captured.value(forHTTPHeaderField: "User-Agent") == "VReader/1.0")
        #expect(captured.value(forHTTPHeaderField: "Referer") == "https://example.com")
        #expect(captured.value(forHTTPHeaderField: "X-Custom") == "test-value")
    }

    // MARK: - Encoding Detection Integration

    @Test func fetchPage_encodingDetect_UTF8() async throws {
        let testURL = URL(string: "https://example.com/utf8")!
        let html = "<html><body>Hello UTF-8</body></html>"

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL, contentType: "text/html; charset=utf-8"),
             html.data(using: .utf8)!)
        }

        let client = BookSourceHTTPClient(session: makeMockSession())
        let result = try await client.fetchPage(url: testURL)
        #expect(result.contains("Hello UTF-8"))
    }

    @Test func fetchPage_encodingDetect_GB2312_fromContentType() async throws {
        let testURL = URL(string: "https://example.com/gb2312")!
        let gbkEnc = WebPageEncodingDetector.gbkEncoding
        let html = "你好世界"
        guard let data = html.data(using: gbkEnc) else {
            Issue.record("Could not encode as GBK")
            return
        }

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL, contentType: "text/html; charset=gb2312"), data)
        }

        let client = BookSourceHTTPClient(session: makeMockSession())
        let result = try await client.fetchPage(url: testURL)
        #expect(result.contains("你好世界"))
    }

    @Test func fetchPage_encodingDetect_noCharset_defaultsUTF8() async throws {
        let testURL = URL(string: "https://example.com/nocharset")!
        let html = "<html><body>Default UTF-8</body></html>"

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL, contentType: "text/html"), html.data(using: .utf8)!)
        }

        let client = BookSourceHTTPClient(session: makeMockSession())
        let result = try await client.fetchPage(url: testURL)
        #expect(result.contains("Default UTF-8"))
    }

    // MARK: - Explicit Encoding Override

    @Test func fetchPage_explicitEncoding_overridesDetection() async throws {
        let testURL = URL(string: "https://example.com/override")!
        let gbkEnc = WebPageEncodingDetector.gbkEncoding
        let html = "中文内容"
        guard let data = html.data(using: gbkEnc) else {
            Issue.record("Could not encode as GBK")
            return
        }

        // Content-Type says nothing about charset, but caller knows it's GBK
        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL, contentType: "text/html"), data)
        }

        let client = BookSourceHTTPClient(session: makeMockSession())
        let result = try await client.fetchPage(url: testURL, encoding: gbkEnc)
        #expect(result.contains("中文内容"))
    }

    // MARK: - Rate Limiting

    @Test func rateLimit_respectsDelay() async throws {
        let testURL = URL(string: "https://example.com/limited")!
        let html = "<html><body>OK</body></html>"

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL), html.data(using: .utf8)!)
        }

        let client = BookSourceHTTPClient(
            session: makeMockSession(),
            rateLimitDelay: 0.1 // 100ms between requests
        )

        let start = ContinuousClock.now

        // Make two sequential requests
        _ = try await client.fetchPage(url: testURL)
        _ = try await client.fetchPage(url: testURL)

        let elapsed = ContinuousClock.now - start

        // Second request should have waited at least 100ms
        #expect(elapsed >= .milliseconds(90), "Expected rate limit delay of ~100ms, got \(elapsed)")
    }

    // MARK: - Empty Response

    @Test func fetchPage_emptyBody_returnsEmptyString() async throws {
        let testURL = URL(string: "https://example.com/empty")!

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL), Data())
        }

        let client = BookSourceHTTPClient(session: makeMockSession())
        let result = try await client.fetchPage(url: testURL)
        #expect(result.isEmpty)
    }

    // MARK: - Download File

    @Test func downloadFile_success() async throws {
        let testURL = URL(string: "https://example.com/file.epub")!
        let fileData = Data("fake epub content".utf8)

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL, contentType: "application/epub+zip"), fileData)
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_download_\(UUID().uuidString).epub")

        let client = BookSourceHTTPClient(session: makeMockSession())
        try await client.downloadFile(url: testURL, to: destination)

        #expect(FileManager.default.fileExists(atPath: destination.path))
        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == fileData)

        // Cleanup
        try? FileManager.default.removeItem(at: destination)
    }

    // MARK: - Default User-Agent

    @Test func fetchPage_defaultUserAgent_sent() async throws {
        let testURL = URL(string: "https://example.com/page")!
        let html = "<html><body>OK</body></html>"

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL), html.data(using: .utf8)!)
        }

        let client = BookSourceHTTPClient(session: makeMockSession())
        _ = try await client.fetchPage(url: testURL)

        #expect(MockURLProtocol.capturedRequests.count == 1)
        let ua = MockURLProtocol.capturedRequests[0].value(forHTTPHeaderField: "User-Agent")
        #expect(ua != nil, "Default User-Agent should be set")
        #expect(ua?.contains("VReader") == true)
    }

    // MARK: - Concurrent Safety

    @Test func fetchPage_concurrent_safe() async throws {
        let testURL = URL(string: "https://example.com/concurrent")!
        let html = "<html><body>OK</body></html>"

        MockURLProtocol.requestHandler = { _ in
            (mockResponse(url: testURL), html.data(using: .utf8)!)
        }

        let client = BookSourceHTTPClient(session: makeMockSession())

        // Fire multiple concurrent requests — actor should handle safely
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await client.fetchPage(url: testURL)
                }
            }
            for try await result in group {
                #expect(result.contains("OK"))
            }
        }
    }
}
