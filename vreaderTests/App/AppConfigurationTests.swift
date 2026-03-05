// Purpose: Tests for AppConfiguration — environment resolution, API URLs, and defaults.

import Testing
import Foundation
@testable import vreader

@Suite("AppConfiguration")
struct AppConfigurationTests {

    // MARK: - Environment Enum

    @Test func environmentHasAllCases() {
        #expect(AppEnvironment.allCases.count == 3)
        #expect(AppEnvironment.allCases.contains(.dev))
        #expect(AppEnvironment.allCases.contains(.staging))
        #expect(AppEnvironment.allCases.contains(.prod))
    }

    @Test func environmentRawValues() {
        #expect(AppEnvironment.dev.rawValue == "dev")
        #expect(AppEnvironment.staging.rawValue == "staging")
        #expect(AppEnvironment.prod.rawValue == "prod")
    }

    @Test func environmentIsSendable() {
        let env: any Sendable = AppEnvironment.dev
        #expect(env is AppEnvironment)
    }

    // MARK: - Environment Resolution from Bundle

    @Test func resolveDevEnvironment() {
        let config = AppConfiguration(
            bundleEnvironmentValue: "dev"
        )
        #expect(config.environment == .dev)
    }

    @Test func resolveStagingEnvironment() {
        let config = AppConfiguration(
            bundleEnvironmentValue: "staging"
        )
        #expect(config.environment == .staging)
    }

    @Test func resolveProdEnvironment() {
        let config = AppConfiguration(
            bundleEnvironmentValue: "prod"
        )
        #expect(config.environment == .prod)
    }

    @Test func caseInsensitiveEnvironmentResolution() {
        let config = AppConfiguration(
            bundleEnvironmentValue: "DEV"
        )
        #expect(config.environment == .dev)
    }

    @Test func mixedCaseEnvironmentResolution() {
        let config = AppConfiguration(
            bundleEnvironmentValue: "Staging"
        )
        #expect(config.environment == .staging)
    }

    @Test func whitespaceEnvironmentTrimmed() {
        let config = AppConfiguration(
            bundleEnvironmentValue: "  dev  "
        )
        #expect(config.environment == .dev)
    }

    @Test func unknownEnvironmentDefaultsToProd() {
        let config = AppConfiguration(
            bundleEnvironmentValue: "unknown"
        )
        #expect(config.environment == .prod)
    }

    @Test func emptyStringDefaultsToProd() {
        let config = AppConfiguration(
            bundleEnvironmentValue: ""
        )
        #expect(config.environment == .prod)
    }

    @Test func nilEnvironmentDefaultsToProd() {
        let config = AppConfiguration(
            bundleEnvironmentValue: nil
        )
        #expect(config.environment == .prod)
    }

    // MARK: - API Base URLs

    @Test func devAPIBaseURL() {
        let config = AppConfiguration(bundleEnvironmentValue: "dev")
        #expect(config.apiBaseURL.absoluteString == "http://localhost:8080/api")
    }

    @Test func stagingAPIBaseURL() {
        let config = AppConfiguration(bundleEnvironmentValue: "staging")
        #expect(config.apiBaseURL.absoluteString == "https://staging-api.vreader.app/api")
    }

    @Test func prodAPIBaseURL() {
        let config = AppConfiguration(bundleEnvironmentValue: "prod")
        #expect(config.apiBaseURL.absoluteString == "https://api.vreader.app/api")
    }

    // MARK: - Retry and Timeout Defaults

    @Test func defaultRetryCount() {
        let config = AppConfiguration(bundleEnvironmentValue: "prod")
        #expect(config.retryCount == 3)
    }

    @Test func defaultTimeoutSeconds() {
        let config = AppConfiguration(bundleEnvironmentValue: "prod")
        #expect(config.timeoutSeconds == 30.0)
    }

    @Test func devTimeoutIsShorter() {
        let config = AppConfiguration(bundleEnvironmentValue: "dev")
        #expect(config.timeoutSeconds == 10.0)
    }

    // MARK: - Sendable

    @Test func configurationIsSendable() {
        let config: any Sendable = AppConfiguration(bundleEnvironmentValue: "prod")
        #expect(config is AppConfiguration)
    }

    // MARK: - Default Initializer

    @Test func defaultInitializerDefaultsToProdInTestHost() {
        // Test host bundle does not have VReaderEnvironment key, so should default to prod
        let config = AppConfiguration()
        #expect(config.environment == .prod)
    }
}
