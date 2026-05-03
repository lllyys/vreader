// Purpose: Regression tests for bug #110 — iOS App Transport Security must
// allow plain HTTP to user-entered WebDAV endpoints (Tailscale, NAS, etc.).
// Localhost works without an exception because iOS exempts loopback; this
// suite covers the non-loopback path that ATS blocks by default.
//
// Two tests, two layers of evidence:
// 1. Bundle.main.NSAppTransportSecurity asserts the build-time config.
// 2. URLSession.dataTask to a non-loopback HTTP URL asserts the runtime
//    behavior — the request must NOT fail with
//    URLError.appTransportSecurityRequiresSecureConnection.
//
// @coordinates-with: project.yml (NSAppTransportSecurity config),
//   vreader/Services/Backup/WebDAVClient.swift (consumer of the URL session)

import Testing
import Foundation

@Suite("WebDAV ATS configuration — bug #110")
struct WebDAVATSTests {

    @Test("Bundle.main NSAppTransportSecurity allows plain HTTP")
    func infoPlist_AllowsArbitraryLoads() {
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        #expect(ats != nil, "NSAppTransportSecurity must be set in Info.plist")
        #expect(
            ats?["NSAllowsArbitraryLoads"] as? Bool == true,
            "NSAllowsArbitraryLoads must be YES so user-entered HTTP WebDAV URLs (Tailscale, NAS) work — the app's purpose is connecting to arbitrary user-controlled WebDAV servers, so per-domain exceptions don't fit"
        )
    }

    @Test("URLSession does not fail with ATS error on non-loopback HTTP")
    func urlSession_NonLoopbackHTTP_doesNotFailWithATS() async {
        // TEST-NET-2 (RFC 5737) — guaranteed unreachable, no real server runs here.
        // ATS check happens BEFORE the network call, so if the fix is wrong, we get
        // .appTransportSecurityRequiresSecureConnection. If the fix is right, we get
        // a network-level error (cannotConnectToHost / timedOut) — which is fine.
        let url = URL(string: "http://198.51.100.1:9999/")!
        var request = URLRequest(url: url, timeoutInterval: 1.0)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")

        do {
            _ = try await URLSession.shared.data(for: request)
            // Highly unlikely against TEST-NET, but if it succeeds, ATS clearly didn't block.
        } catch let error as URLError {
            #expect(
                error.code != .appTransportSecurityRequiresSecureConnection,
                "Plain HTTP to a non-loopback host must not be blocked by ATS — got \(error.code) which is fine; .appTransportSecurityRequiresSecureConnection means the fix is missing"
            )
        } catch {
            // A non-URLError isn't evidence ATS worked — surface it so we can
            // investigate rather than silently passing.
            Issue.record("Unexpected non-URLError from URLSession: \(error). ATS check is inconclusive.")
        }
    }
}
