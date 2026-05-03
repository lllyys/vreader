// Purpose: Tests for WebDAVClient — URLSession-based WebDAV operations.
// Validates PROPFIND parsing, PUT/GET/DELETE HTTP methods, authentication,
// connection testing, and error handling.
//
// @coordinates-with: WebDAVClient.swift, WebDAVProvider.swift

import Testing
import Foundation
@testable import vreader

// MARK: - WebDAVClient Tests

@Suite("WebDAVClient")
struct WebDAVClientTests {

    // MARK: - Helpers

    /// Creates a client with a stub session for testing.
    private func makeClient(
        serverURL: String = "https://dav.example.com/dav/",
        username: String = "user",
        password: String = "pass"
    ) -> WebDAVClient {
        WebDAVClient(
            serverURL: URL(string: serverURL)!,
            username: username,
            password: password
        )
    }

    // MARK: - Initialization

    @Test func init_storesCredentials() {
        let client = makeClient(
            serverURL: "https://dav.example.com/dav/",
            username: "testuser",
            password: "testpass"
        )
        #expect(client.serverURL.absoluteString == "https://dav.example.com/dav/")
        #expect(client.username == "testuser")
    }

    @Test func init_normalizesTrailingSlash() {
        let client = makeClient(serverURL: "https://dav.example.com/dav")
        // Should ensure trailing slash for directory operations
        #expect(client.serverURL.absoluteString.hasSuffix("/"))
    }

    // MARK: - URL Building

    @Test func buildURL_appendsPathToServerURL() {
        let client = makeClient(serverURL: "https://dav.example.com/dav/")
        let url = client.buildURL(path: "VReader/backups/test.zip")
        #expect(url.absoluteString == "https://dav.example.com/dav/VReader/backups/test.zip")
    }

    @Test func buildURL_handlesSpecialCharacters() {
        let client = makeClient(serverURL: "https://dav.example.com/dav/")
        let url = client.buildURL(path: "VReader/backups/2024-01-01T12:00:00.zip")
        #expect(url.absoluteString.contains("2024-01-01T12"))
    }

    // MARK: - Auth Header

    @Test func authHeader_createsValidBasicAuth() {
        let client = makeClient(username: "user", password: "pass")
        let header = client.authorizationHeader
        // Base64 of "user:pass" = "dXNlcjpwYXNz"
        #expect(header == "Basic dXNlcjpwYXNz")
    }

    @Test func authHeader_handlesSpecialCharactersInPassword() {
        let client = makeClient(username: "user", password: "p@ss:w0rd!")
        let header = client.authorizationHeader
        let expected = "Basic " + Data("user:p@ss:w0rd!".utf8).base64EncodedString()
        #expect(header == expected)
    }

    // MARK: - PROPFIND Parsing

    @Test func parsePROPFIND_validXML_returnsEntries() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/dav/VReader/backups/20240101T120000.vreader.zip</D:href>
            <D:propstat>
              <D:prop>
                <D:getcontentlength>1048576</D:getcontentlength>
                <D:getlastmodified>Mon, 01 Jan 2024 12:00:00 GMT</D:getlastmodified>
                <D:resourcetype/>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let entries = try WebDAVClient.parsePROPFINDResponse(Data(xml.utf8))
        #expect(entries.count == 1)
        #expect(entries[0].href.contains("20240101T120000.vreader.zip"))
        #expect(entries[0].contentLength == 1_048_576)
        #expect(entries[0].isDirectory == false)
    }

    @Test func parsePROPFIND_multipleEntries_returnsAll() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/dav/VReader/backups/</D:href>
            <D:propstat>
              <D:prop>
                <D:resourcetype><D:collection/></D:resourcetype>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
          <D:response>
            <D:href>/dav/VReader/backups/first.vreader.zip</D:href>
            <D:propstat>
              <D:prop>
                <D:getcontentlength>500</D:getcontentlength>
                <D:getlastmodified>Mon, 01 Jan 2024 12:00:00 GMT</D:getlastmodified>
                <D:resourcetype/>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
          <D:response>
            <D:href>/dav/VReader/backups/second.vreader.zip</D:href>
            <D:propstat>
              <D:prop>
                <D:getcontentlength>1000</D:getcontentlength>
                <D:getlastmodified>Tue, 02 Jan 2024 12:00:00 GMT</D:getlastmodified>
                <D:resourcetype/>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let entries = try WebDAVClient.parsePROPFINDResponse(Data(xml.utf8))
        // Should include directory + 2 files = 3 entries
        #expect(entries.count == 3)
        let files = entries.filter { !$0.isDirectory }
        #expect(files.count == 2)
    }

    @Test func parsePROPFIND_directoryEntry_markedAsDirectory() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/dav/VReader/backups/</D:href>
            <D:propstat>
              <D:prop>
                <D:resourcetype><D:collection/></D:resourcetype>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let entries = try WebDAVClient.parsePROPFINDResponse(Data(xml.utf8))
        #expect(entries.count == 1)
        #expect(entries[0].isDirectory == true)
    }

    @Test func parsePROPFIND_emptyResponse_returnsEmpty() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
        </D:multistatus>
        """
        let entries = try WebDAVClient.parsePROPFINDResponse(Data(xml.utf8))
        #expect(entries.isEmpty)
    }

    @Test func parsePROPFIND_invalidXML_throwsError() {
        let badData = Data("not xml at all".utf8)
        #expect(throws: WebDAVError.self) {
            try WebDAVClient.parsePROPFINDResponse(badData)
        }
    }

    @Test func parsePROPFIND_missingContentLength_defaultsToZero() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/dav/VReader/backups/nosize.vreader.zip</D:href>
            <D:propstat>
              <D:prop>
                <D:resourcetype/>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let entries = try WebDAVClient.parsePROPFINDResponse(Data(xml.utf8))
        #expect(entries.count == 1)
        #expect(entries[0].contentLength == 0)
    }

    // MARK: - Request Building

    @Test func buildPROPFINDRequest_hasCorrectMethodAndHeaders() {
        let client = makeClient()
        let request = client.buildPROPFINDRequest(path: "VReader/backups/")
        #expect(request.httpMethod == "PROPFIND")
        #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
        #expect(request.value(forHTTPHeaderField: "Depth") == "1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/xml")
    }

    @Test func buildPUTRequest_hasCorrectMethodAndBody() {
        let client = makeClient()
        let data = Data("test content".utf8)
        let request = client.buildPUTRequest(path: "VReader/backups/test.zip", data: data)
        #expect(request.httpMethod == "PUT")
        #expect(request.httpBody == data)
        #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
    }

    @Test func buildGETRequest_hasCorrectMethod() {
        let client = makeClient()
        let request = client.buildGETRequest(path: "VReader/backups/test.zip")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
    }

    @Test func buildDELETERequest_hasCorrectMethod() {
        let client = makeClient()
        let request = client.buildDELETERequest(path: "VReader/backups/test.zip")
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
    }

    @Test func buildMKCOLRequest_hasCorrectMethod() {
        let client = makeClient()
        let request = client.buildMKCOLRequest(path: "VReader/backups/")
        #expect(request.httpMethod == "MKCOL")
        #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
    }

    // MARK: - MOVE + PROPFIND-exists (feature #46 WI-3)

    @Test func buildMOVERequest_hasCorrectMethodAndDestination() {
        let client = makeClient()
        let request = client.buildMOVERequest(
            fromPath: "VReader/uploads/tmp/abc.part",
            toPath: "VReader/books/epub/sha_1024.epub"
        )
        #expect(request.httpMethod == "MOVE")
        #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
        let dest = request.value(forHTTPHeaderField: "Destination") ?? ""
        // Destination is an absolute URL on the same server (RFC 4918 §10.3).
        #expect(dest == "https://dav.example.com/dav/VReader/books/epub/sha_1024.epub")
        // Default Overwrite: F so a pre-existing destination is preserved
        // (content-addressing means identical bytes already converged).
        #expect(request.value(forHTTPHeaderField: "Overwrite") == "F")
    }

    @Test func buildMOVERequest_overwriteTrue_setsOverwriteHeader() {
        let client = makeClient()
        let request = client.buildMOVERequest(
            fromPath: "from",
            toPath: "to",
            overwrite: true
        )
        #expect(request.value(forHTTPHeaderField: "Overwrite") == "T")
    }

    @Test func buildPROPFINDExistsRequest_usesDepthZero() {
        // Depth: 0 distinguishes "tell me about THIS resource" from the
        // existing buildPROPFINDRequest which uses Depth: 1 to enumerate
        // children. Used by `existsWithSize` to cheaply check a single blob.
        let client = makeClient()
        let request = client.buildPROPFINDExistsRequest(
            path: "VReader/books/epub/sha_1024.epub"
        )
        #expect(request.httpMethod == "PROPFIND")
        #expect(request.value(forHTTPHeaderField: "Depth") == "0")
        #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/xml")
        // Body asks for getcontentlength + getlastmodified + resourcetype.
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(body.contains("<D:getcontentlength/>"))
    }

    // MARK: - HTTP Status Handling

    @Test func checkStatus_200_succeeds() throws {
        try WebDAVClient.checkHTTPStatus(200, url: URL(string: "https://x.com")!)
    }

    @Test func checkStatus_201_succeeds() throws {
        try WebDAVClient.checkHTTPStatus(201, url: URL(string: "https://x.com")!)
    }

    @Test func checkStatus_204_succeeds() throws {
        try WebDAVClient.checkHTTPStatus(204, url: URL(string: "https://x.com")!)
    }

    @Test func checkStatus_207_succeeds() throws {
        try WebDAVClient.checkHTTPStatus(207, url: URL(string: "https://x.com")!)
    }

    @Test func checkStatus_401_throwsAuthError() {
        #expect(throws: WebDAVError.self) {
            try WebDAVClient.checkHTTPStatus(401, url: URL(string: "https://x.com")!)
        }
    }

    @Test func checkStatus_403_throwsAuthError() {
        #expect(throws: WebDAVError.self) {
            try WebDAVClient.checkHTTPStatus(403, url: URL(string: "https://x.com")!)
        }
    }

    @Test func checkStatus_404_throwsNotFoundError() {
        #expect(throws: WebDAVError.self) {
            try WebDAVClient.checkHTTPStatus(404, url: URL(string: "https://x.com")!)
        }
    }

    @Test func checkStatus_500_throwsServerError() {
        #expect(throws: WebDAVError.self) {
            try WebDAVClient.checkHTTPStatus(500, url: URL(string: "https://x.com")!)
        }
    }

    @Test func checkStatus_507_throwsQuotaError() {
        #expect(throws: WebDAVError.self) {
            try WebDAVClient.checkHTTPStatus(507, url: URL(string: "https://x.com")!)
        }
    }
}
