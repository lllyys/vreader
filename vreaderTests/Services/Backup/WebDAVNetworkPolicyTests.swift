// Purpose: Tests for WebDAVNetworkPolicy — the wifiOnly preference,
// path-change handling, and the shouldStart() gate the lazy-download
// coordinator and "Restore all" UI consult before initiating
// transfers. Feature #47 WI-3c.

import Testing
import Foundation
@testable import vreader

/// Hand-built mock path monitor. Tests configure the initial path,
/// construct a policy with this monitor, then call `simulate(_:)` to
/// drive transitions.
final class MockNetworkPathMonitor: NetworkPathMonitoring, @unchecked Sendable {
    var onPathChange: (@Sendable (WebDAVNetworkInterface) -> Void)?
    private(set) var didStart = false
    private(set) var didCancel = false

    func start() { didStart = true }
    func cancel() { didCancel = true }
    func simulate(_ interface: WebDAVNetworkInterface) { onPathChange?(interface) }
}

@MainActor
@Suite("WebDAVNetworkPolicy — feature #47 WI-3c")
struct WebDAVNetworkPolicyTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "vreader.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Initial state

    @Test func defaults_wifiOnlyTrue_whenKeyMissing() {
        let defaults = makeDefaults()
        let monitor = MockNetworkPathMonitor()
        let policy = WebDAVNetworkPolicy(defaults: defaults, monitor: monitor)
        #expect(policy.wifiOnly == true)
        // Persisted so the next launch reads true even if the user
        // never touched the toggle.
        #expect(defaults.bool(forKey: WebDAVNetworkPolicy.wifiOnlyKey) == true)
    }

    @Test func defaults_readsExistingFalseFromUserDefaults() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: WebDAVNetworkPolicy.wifiOnlyKey)
        let policy = WebDAVNetworkPolicy(defaults: defaults, monitor: MockNetworkPathMonitor())
        #expect(policy.wifiOnly == false)
    }

    @Test func currentInterface_startsAsUnknown() {
        let policy = WebDAVNetworkPolicy(defaults: makeDefaults(), monitor: MockNetworkPathMonitor())
        #expect(policy.currentInterface == .unknown)
    }

    @Test func init_startsTheMonitor() {
        let monitor = MockNetworkPathMonitor()
        _ = WebDAVNetworkPolicy(defaults: makeDefaults(), monitor: monitor)
        #expect(monitor.didStart)
    }

    // MARK: - wifiOnly mutation persists

    @Test func writingWifiOnly_persistsToDefaults() {
        let defaults = makeDefaults()
        let policy = WebDAVNetworkPolicy(defaults: defaults, monitor: MockNetworkPathMonitor())
        policy.wifiOnly = false
        #expect(defaults.bool(forKey: WebDAVNetworkPolicy.wifiOnlyKey) == false)
    }

    // MARK: - Path-change updates currentInterface

    @Test func pathChange_updatesCurrentInterface() async {
        let monitor = MockNetworkPathMonitor()
        let policy = WebDAVNetworkPolicy(defaults: makeDefaults(), monitor: monitor)
        monitor.simulate(.wifi)
        // pathChange handler hops to MainActor via Task — yield once
        // so the assignment lands before assertions.
        await Task.yield()
        #expect(policy.currentInterface == .wifi)

        monitor.simulate(.cellular)
        await Task.yield()
        #expect(policy.currentInterface == .cellular)
    }

    // MARK: - shouldStart() truth table

    @Test func shouldStart_wifiOnlyFalse_alwaysTrue() async {
        let defaults = makeDefaults()
        defaults.set(false, forKey: WebDAVNetworkPolicy.wifiOnlyKey)
        let monitor = MockNetworkPathMonitor()
        let policy = WebDAVNetworkPolicy(defaults: defaults, monitor: monitor)
        // Even on cellular / no network / unknown.
        #expect(policy.shouldStart())
        monitor.simulate(.cellular); await Task.yield()
        #expect(policy.shouldStart())
        monitor.simulate(.none); await Task.yield()
        #expect(policy.shouldStart())
    }

    @Test func shouldStart_wifiOnlyTrue_andWifi_returnsTrue() async {
        let monitor = MockNetworkPathMonitor()
        let policy = WebDAVNetworkPolicy(defaults: makeDefaults(), monitor: monitor)
        monitor.simulate(.wifi); await Task.yield()
        #expect(policy.shouldStart())
    }

    @Test func shouldStart_wifiOnlyTrue_andCellular_returnsFalse() async {
        let monitor = MockNetworkPathMonitor()
        let policy = WebDAVNetworkPolicy(defaults: makeDefaults(), monitor: monitor)
        monitor.simulate(.cellular); await Task.yield()
        #expect(policy.shouldStart() == false)
    }

    @Test func shouldStart_wifiOnlyTrue_andNoNetwork_returnsFalse() async {
        let monitor = MockNetworkPathMonitor()
        let policy = WebDAVNetworkPolicy(defaults: makeDefaults(), monitor: monitor)
        monitor.simulate(.none); await Task.yield()
        #expect(policy.shouldStart() == false)
    }

    @Test func shouldStart_wifiOnlyTrue_andUnknown_returnsFalse() {
        // Conservative: don't initiate downloads before the first
        // path-change tick lands.
        let policy = WebDAVNetworkPolicy(defaults: makeDefaults(), monitor: MockNetworkPathMonitor())
        #expect(policy.currentInterface == .unknown)
        #expect(policy.shouldStart() == false)
    }

    // MARK: - Toggle flips outcome under fixed interface

    @Test func wifiOnlyToggle_changesShouldStartWhenOnCellular() async {
        let monitor = MockNetworkPathMonitor()
        let policy = WebDAVNetworkPolicy(defaults: makeDefaults(), monitor: monitor)
        monitor.simulate(.cellular); await Task.yield()
        #expect(policy.shouldStart() == false)
        policy.wifiOnly = false
        #expect(policy.shouldStart())
        policy.wifiOnly = true
        #expect(policy.shouldStart() == false)
    }
}
