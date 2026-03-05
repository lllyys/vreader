// Purpose: Centralized app configuration with environment resolution.
// Resolves environment from build settings (Info.plist), provides API base URLs,
// retry/timeout defaults, and acts as the single source of truth for config.
//
// Key decisions:
// - Environment defaults to .prod when the bundle key is missing or unrecognized.
//   This is fail-safe: production is the most restrictive environment.
// - Case-insensitive matching for environment string.
// - Testable: accepts optional bundleEnvironmentValue for injection in tests.
//
// @coordinates-with: FeatureFlags.swift

import Foundation

/// App deployment environment.
enum AppEnvironment: String, Sendable, CaseIterable {
    case dev = "dev"
    case staging = "staging"
    case prod = "prod"
}

/// Centralized configuration resolved from build settings and environment.
struct AppConfiguration: Sendable {

    /// The resolved environment for this app instance.
    let environment: AppEnvironment

    // Pre-validated URL constants — guaranteed valid at compile time.
    private static let devURL = URL(string: "http://localhost:8080/api")!
    private static let stagingURL = URL(string: "https://staging-api.vreader.app/api")!
    private static let prodURL = URL(string: "https://api.vreader.app/api")!

    /// API base URL for the current environment.
    /// Note: Dev uses HTTP for local development only. ATS exceptions are scoped
    /// to localhost in Info.plist and excluded from release builds.
    var apiBaseURL: URL {
        switch environment {
        case .dev: return Self.devURL
        case .staging: return Self.stagingURL
        case .prod: return Self.prodURL
        }
    }

    /// Number of retry attempts for network requests.
    var retryCount: Int {
        switch environment {
        case .dev: return 1
        case .staging: return 2
        case .prod: return 3
        }
    }

    /// Timeout in seconds for network requests.
    var timeoutSeconds: TimeInterval {
        switch environment {
        case .dev: return 10.0
        case .staging: return 20.0
        case .prod: return 30.0
        }
    }

    // MARK: - Initialization

    /// Creates a configuration by reading the environment from Bundle.main.
    init() {
        let bundleValue = Bundle.main.infoDictionary?["VReaderEnvironment"] as? String
        self.init(bundleEnvironmentValue: bundleValue)
    }

    /// Creates a configuration with an explicit environment value (for testing).
    ///
    /// - Parameter bundleEnvironmentValue: The raw environment string from build settings.
    ///   If nil, empty, or unrecognized, defaults to `.prod`.
    init(bundleEnvironmentValue: String?) {
        let trimmed = bundleEnvironmentValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let value = trimmed,
              !value.isEmpty,
              let resolved = AppEnvironment(rawValue: value) else {
            if let raw = bundleEnvironmentValue, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                assertionFailure("Unrecognized VReaderEnvironment value: \"\(raw)\". Defaulting to prod.")
            }
            self.environment = .prod
            return
        }
        #if !DEBUG
        // Safety: release builds must always use prod. Force override rather than
        // relying on assert(), which is stripped from optimized builds.
        if resolved != .prod {
            self.environment = .prod
            return
        }
        #endif
        self.environment = resolved
    }
}

