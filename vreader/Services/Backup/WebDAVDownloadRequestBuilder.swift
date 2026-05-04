// Purpose: Builds the authenticated `URLRequest` the lazy-download
// coordinator hands to its background URLSession. Pure utility — no
// I/O, no actor. Reuses the credentials WebDAVClient already holds so
// we don't fork the auth logic. Feature #47 WI-6 part 2.
//
// @coordinates-with: WebDAVClient.swift, LazyDownloadCoordinator.swift,
//   BlobPath.swift, dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation

struct WebDAVDownloadRequestBuilder: Sendable {

    private let client: WebDAVClient

    init(client: WebDAVClient) {
        self.client = client
    }

    /// Builds a GET URLRequest pointed at `blobPath` (relative to the
    /// WebDAV server root) with the Authorization header pre-set. The
    /// caller hands this to URLSession's `downloadTask(with:)` — the
    /// background session takes the request as-is.
    func authenticatedGETRequest(forBlobPath blobPath: String) -> URLRequest {
        var request = URLRequest(url: client.buildURL(path: blobPath))
        request.httpMethod = "GET"
        request.setValue(client.authorizationHeader, forHTTPHeaderField: "Authorization")
        return request
    }
}
