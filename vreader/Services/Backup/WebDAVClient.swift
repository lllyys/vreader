// Purpose: URLSession-based WebDAV HTTP operations (PROPFIND, PUT, GET, DELETE, MKCOL).
// Provides request building, response parsing, and HTTP status validation.
// Transport protocol enables testing without real HTTP calls.
//
// Key decisions:
// - Stateless struct: each method builds a URLRequest independently.
// - Basic authentication via Authorization header.
// - PROPFIND XML parsed with Foundation's XMLParser (no third-party deps).
// - Transport protocol abstracts actual HTTP calls for testability.
// - Server URL normalized with trailing slash at init.
//
// @coordinates-with: WebDAVProvider.swift, KeychainService.swift

import Foundation

// MARK: - WebDAVError

/// Errors from WebDAV operations.
enum WebDAVError: Error, Sendable, Equatable {
    /// Server returned 401/403.
    case authenticationFailed
    /// Resource not found (404).
    case notFound(String)
    /// Server is unreachable or returned a connection error.
    case connectionFailed(String)
    /// Server returned an unexpected HTTP status code.
    case httpError(Int)
    /// Server is out of storage space (507).
    case quotaExceeded
    /// The PROPFIND response XML could not be parsed.
    case invalidResponse(String)
}

// MARK: - WebDAVEntry

/// A single entry returned by a PROPFIND directory listing.
struct WebDAVEntry: Sendable, Equatable {
    /// The href (path) of the resource.
    let href: String
    /// Content length in bytes (0 if unknown or directory).
    let contentLength: Int64
    /// Last modified date, if available.
    let lastModified: Date?
    /// Whether this entry is a collection (directory).
    let isDirectory: Bool
}

// MARK: - WebDAVTransport Protocol

/// Abstracts WebDAV HTTP operations for testability.
/// Production uses URLSession; tests use MockWebDAVTransport.
protocol WebDAVTransport: Sendable {
    func upload(data: Data, toPath path: String) async throws
    func download(fromPath path: String) async throws -> Data
    func delete(path: String) async throws
    func listDirectory(path: String) async throws -> [WebDAVEntry]
    func createDirectory(path: String) async throws
    func testConnection() async throws
}

// MARK: - WebDAVClient

/// URLSession-based WebDAV client.
///
/// Provides both direct request-building methods (for unit testing request
/// construction) and a `WebDAVTransport` conformance (for integration use).
struct WebDAVClient: Sendable {

    /// The base server URL (with trailing slash).
    let serverURL: URL

    /// The username for Basic auth.
    let username: String

    /// The password for Basic auth (not exposed publicly).
    private let password: String

    /// URLSession for HTTP operations.
    private let session: URLSession

    // MARK: - Init

    /// Creates a WebDAV client.
    ///
    /// - Parameters:
    ///   - serverURL: Base WebDAV URL. Trailing slash is added if missing.
    ///   - username: Auth username.
    ///   - password: Auth password.
    ///   - session: URLSession to use (default: `.shared`).
    init(
        serverURL: URL,
        username: String,
        password: String,
        session: URLSession = .shared
    ) {
        // Normalize trailing slash
        var urlString = serverURL.absoluteString
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        self.serverURL = URL(string: urlString)!
        self.username = username
        self.password = password
        self.session = session
    }

    // MARK: - URL Building

    /// Builds a full URL by appending a relative path to the server URL.
    func buildURL(path: String) -> URL {
        serverURL.appendingPathComponent(path)
    }

    // MARK: - Auth

    /// The Basic auth Authorization header value.
    var authorizationHeader: String {
        let credentials = "\(username):\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    // MARK: - Request Building

    /// Builds a PROPFIND request for directory listing.
    func buildPROPFINDRequest(path: String) -> URLRequest {
        var request = URLRequest(url: buildURL(path: path))
        request.httpMethod = "PROPFIND"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.propfindBody.utf8)
        return request
    }

    /// Builds a PUT request for file upload.
    func buildPUTRequest(path: String, data: Data) -> URLRequest {
        var request = URLRequest(url: buildURL(path: path))
        request.httpMethod = "PUT"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return request
    }

    /// Builds a GET request for file download.
    func buildGETRequest(path: String) -> URLRequest {
        var request = URLRequest(url: buildURL(path: path))
        request.httpMethod = "GET"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        return request
    }

    /// Builds a DELETE request.
    func buildDELETERequest(path: String) -> URLRequest {
        var request = URLRequest(url: buildURL(path: path))
        request.httpMethod = "DELETE"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        return request
    }

    /// Builds a MKCOL request for directory creation.
    /// Forces a trailing slash on the path so Apache-class servers return
    /// 405 (already exists) or 201 (created) directly instead of issuing a
    /// 301 redirect that URLSession's default handler can rewrite into a
    /// method-converted follow-up that fails auth.
    func buildMKCOLRequest(path: String) -> URLRequest {
        let normalized = path.hasSuffix("/") ? path : path + "/"
        var request = URLRequest(url: buildURL(path: normalized))
        request.httpMethod = "MKCOL"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - HTTP Status Validation

    /// Checks an HTTP status code and throws appropriate WebDAVError for failures.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP response status code.
    ///   - url: The URL that was requested (for error messages).
    /// - Throws: `WebDAVError` for non-success status codes.
    static func checkHTTPStatus(_ statusCode: Int, url: URL) throws {
        switch statusCode {
        case 200...299, 207:
            return // Success
        case 401, 403:
            throw WebDAVError.authenticationFailed
        case 404:
            throw WebDAVError.notFound(url.absoluteString)
        case 507:
            throw WebDAVError.quotaExceeded
        case 400...499:
            throw WebDAVError.httpError(statusCode)
        case 500...599:
            throw WebDAVError.httpError(statusCode)
        default:
            throw WebDAVError.httpError(statusCode)
        }
    }

    // MARK: - PROPFIND XML Parsing

    /// Parses a PROPFIND XML response into WebDAVEntry values.
    ///
    /// - Parameter data: The raw XML response body.
    /// - Returns: Array of parsed entries.
    /// - Throws: `WebDAVError.invalidResponse` if XML is malformed.
    static func parsePROPFINDResponse(_ data: Data) throws -> [WebDAVEntry] {
        let parser = PROPFINDParser(data: data)
        return try parser.parse()
    }

    // MARK: - Private

    /// Standard PROPFIND request body asking for common properties.
    private static let propfindBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <D:propfind xmlns:D="DAV:">
      <D:prop>
        <D:getcontentlength/>
        <D:getlastmodified/>
        <D:resourcetype/>
      </D:prop>
    </D:propfind>
    """
}

// MARK: - WebDAVTransport Conformance

extension WebDAVClient: WebDAVTransport {

    func upload(data: Data, toPath path: String) async throws {
        let request = buildPUTRequest(path: path, data: data)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.connectionFailed("Invalid response")
        }
        try Self.checkHTTPStatus(httpResponse.statusCode, url: request.url!)
    }

    func download(fromPath path: String) async throws -> Data {
        let request = buildGETRequest(path: path)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.connectionFailed("Invalid response")
        }
        try Self.checkHTTPStatus(httpResponse.statusCode, url: request.url!)
        return data
    }

    func delete(path: String) async throws {
        let request = buildDELETERequest(path: path)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.connectionFailed("Invalid response")
        }
        try Self.checkHTTPStatus(httpResponse.statusCode, url: request.url!)
    }

    func listDirectory(path: String) async throws -> [WebDAVEntry] {
        let request = buildPROPFINDRequest(path: path)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.connectionFailed("Invalid response")
        }
        try Self.checkHTTPStatus(httpResponse.statusCode, url: request.url!)
        return try Self.parsePROPFINDResponse(data)
    }

    func createDirectory(path: String) async throws {
        let request = buildMKCOLRequest(path: path)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.connectionFailed("Invalid response")
        }
        // 405 = already exists, treat as success
        let statusCode = httpResponse.statusCode
        if statusCode != 405 {
            try Self.checkHTTPStatus(statusCode, url: request.url!)
        }
    }

    func testConnection() async throws {
        let request = buildPROPFINDRequest(path: "")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.connectionFailed("Invalid response")
        }
        try Self.checkHTTPStatus(httpResponse.statusCode, url: request.url!)
    }
}

// MARK: - PROPFIND XML Parser (see PROPFINDParser.swift)
