// Purpose: Wi-Fi-only gate for lazy book-blob downloads. Owns a single
// `NWPathMonitor` and publishes the current interface kind so the
// lazy-download coordinator (and "Restore all" UI) can defer
// transfers to Wi-Fi when the user has opted in.
//
// Why not URLSession.allowsCellularAccess: setting that flag to false
// CANCELS the task when the interface flips to cellular mid-flight
// instead of pausing it. We want pause-and-resume semantics, so we set
// `allowsCellularAccess = true` on the background session and gate at
// the enqueue layer (WI-4a) using `policy.shouldStart()`.
//
// Feature #47 WI-3c.
//
// @coordinates-with: LazyDownloadCoordinator.swift,
//   BackgroundDownloadSession.swift,
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation
import Network
import OSLog
import Observation

private let log = Logger(subsystem: "com.vreader.app", category: "WebDAVNetworkPolicy")

/// Current network interface for downloads. `.unknown` is the initial
/// state before NWPathMonitor's first callback lands.
enum WebDAVNetworkInterface: String, Sendable, Equatable {
    case unknown
    case none
    case cellular
    case wifi
}

/// Test seam for `NWPathMonitor`. Production wraps the real monitor;
/// tests inject a controllable fake that fires path-change events on
/// demand.
protocol NetworkPathMonitoring: AnyObject, Sendable {
    /// Closure fired when the path interface changes. The closure is
    /// invoked on an unspecified queue — implementations should hop to
    /// the consumer's actor before mutating state.
    var onPathChange: (@Sendable (WebDAVNetworkInterface) -> Void)? { get set }
    func start()
    func cancel()
}

/// Production implementation backed by `NWPathMonitor`. Single instance
/// owned by `WebDAVNetworkPolicy`; cancelled on deinit.
final class ProductionNetworkPathMonitor: NetworkPathMonitoring, @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    var onPathChange: (@Sendable (WebDAVNetworkInterface) -> Void)?

    init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.vreader.app.WebDAVNetworkPolicy.monitor")
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let interface = Self.classify(path)
            self?.onPathChange?(interface)
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }

    deinit { monitor.cancel() }

    private static func classify(_ path: NWPath) -> WebDAVNetworkInterface {
        guard path.status == .satisfied else { return .none }
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return .wifi
        }
        if path.usesInterfaceType(.cellular) {
            return .cellular
        }
        // Loopback or unknown — treat as Wi-Fi-equivalent (typical for
        // simulator + tethered testing). Cellular remains the only
        // restricted case under wifiOnly.
        return .wifi
    }
}

/// MainActor-isolated, observable Wi-Fi-only gate. Persists the
/// `wifiOnly` toggle in UserDefaults so the user's preference survives
/// app launches.
@MainActor
@Observable
final class WebDAVNetworkPolicy {

    /// Default-true: download books only on Wi-Fi unless the user
    /// explicitly opts in to cellular.
    static let wifiOnlyKey = "com.vreader.webdav.wifiOnly"

    /// Most recent interface from the path monitor. `.unknown` until
    /// the first path-change callback lands.
    private(set) var currentInterface: WebDAVNetworkInterface = .unknown

    /// User preference. Reads from UserDefaults on construction;
    /// writes propagate to UserDefaults synchronously. Default true
    /// when the key is missing.
    var wifiOnly: Bool {
        didSet {
            defaults.set(wifiOnly, forKey: Self.wifiOnlyKey)
            log.info("wifiOnly = \(self.wifiOnly, privacy: .public)")
        }
    }

    private let defaults: UserDefaults
    private let monitor: any NetworkPathMonitoring

    init(defaults: UserDefaults = .standard, monitor: (any NetworkPathMonitoring)? = nil) {
        self.defaults = defaults
        // Default true if the key has never been written.
        if defaults.object(forKey: Self.wifiOnlyKey) == nil {
            self.wifiOnly = true
            defaults.set(true, forKey: Self.wifiOnlyKey)
        } else {
            self.wifiOnly = defaults.bool(forKey: Self.wifiOnlyKey)
        }
        self.monitor = monitor ?? ProductionNetworkPathMonitor()
        self.monitor.onPathChange = { [weak self] interface in
            Task { @MainActor [weak self] in
                self?.currentInterface = interface
            }
        }
        self.monitor.start()
    }

    deinit {
        monitor.cancel()
    }

    /// Returns true when downloads may start now. Used by the enqueue
    /// path (WI-4a) and by "Restore all" guards.
    /// - `wifiOnly == false` → always true.
    /// - `wifiOnly == true && interface == .wifi` → true.
    /// - `wifiOnly == true && interface in [.cellular, .none, .unknown]` → false.
    ///   (`.unknown` defaults to false because we haven't yet observed
    ///   the interface and shouldn't risk burning cellular on a wrong
    ///   guess; the first path-change tick lands fast in practice.)
    func shouldStart() -> Bool {
        if !wifiOnly { return true }
        return currentInterface == .wifi
    }
}
