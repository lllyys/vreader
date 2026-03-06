// Purpose: Tests for SyncService — feature flag guard, metadata sync coordination,
// file download lifecycle, status updates, error propagation.

import Testing
import Foundation
@testable import vreader

@Suite("SyncService")
struct SyncServiceTests {

    // MARK: - Feature Flag Guard

    @Test func syncMetadataNoOpWhenFlagDisabled() async {
        let flags = FeatureFlags(environment: .prod)
        // sync is OFF by default
        let service = SyncService(featureFlags: flags)
        let result = await service.syncMetadata(for: SyncTestHelpers.fingerprintA.canonicalKey)
        #expect(result == .disabled)
    }

    @Test func requestFileDownloadNoOpWhenFlagDisabled() async {
        let flags = FeatureFlags(environment: .prod)
        let service = SyncService(featureFlags: flags)
        let result = await service.requestFileDownload(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey
        )
        #expect(result == .disabled)
    }

    @Test func syncStatusIsDisabledWhenFlagOff() async {
        let flags = FeatureFlags(environment: .prod)
        let service = SyncService(featureFlags: flags)
        let status = await service.syncStatus
        #expect(status == .disabled)
    }

    // MARK: - Feature Flag Enabled

    @Test func syncMetadataReturnsIdleWhenEnabled() async {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.sync, value: true)
        let service = SyncService(featureFlags: flags)
        let result = await service.syncMetadata(for: SyncTestHelpers.fingerprintA.canonicalKey)
        #expect(result == .success)
    }

    @Test func requestFileDownloadReturnsQueuedWhenEnabled() async {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.sync, value: true)
        let service = SyncService(featureFlags: flags)
        let result = await service.requestFileDownload(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey
        )
        #expect(result == .queued)
    }

    @Test func syncStatusIsIdleWhenEnabled() async {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.sync, value: true)
        let service = SyncService(featureFlags: flags)
        let status = await service.syncStatus
        #expect(status == .idle)
    }

    // MARK: - Status Monitor

    @Test @MainActor func statusMonitorInitialStateIsDisabled() {
        let monitor = SyncStatusMonitor()
        #expect(monitor.status == .disabled)
        #expect(monitor.lastSyncDate == nil)
        #expect(monitor.pendingChangesCount == 0)
        #expect(monitor.errorDescription == nil)
    }

    @Test @MainActor func statusMonitorUpdatesStatus() {
        let monitor = SyncStatusMonitor()
        monitor.update(status: .idle)
        #expect(monitor.status == .idle)
    }

    @Test @MainActor func statusMonitorTracksErrors() {
        let monitor = SyncStatusMonitor()
        monitor.update(status: .error("Network unavailable"))
        #expect(monitor.status == .error("Network unavailable"))
        #expect(monitor.errorDescription == "Network unavailable")
    }

    @Test @MainActor func statusMonitorTracksLastSyncDate() {
        let monitor = SyncStatusMonitor()
        let now = Date()
        monitor.update(status: .idle, lastSyncDate: now)
        #expect(monitor.lastSyncDate == now)
    }

    @Test @MainActor func statusMonitorTracksPendingChanges() {
        let monitor = SyncStatusMonitor()
        monitor.update(pendingChangesCount: 5)
        #expect(monitor.pendingChangesCount == 5)
    }

    // MARK: - File Availability in SyncService

    @Test func fileAvailabilityDefaultIsMetadataOnly() async {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.sync, value: true)
        let service = SyncService(featureFlags: flags)
        let state = await service.fileAvailability(
            for: SyncTestHelpers.fingerprintA.canonicalKey
        )
        #expect(state == .metadataOnly)
    }

    @Test func fileAvailabilityTransitionsOnDownloadRequest() async {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.sync, value: true)
        let service = SyncService(featureFlags: flags)
        _ = await service.requestFileDownload(
            bookFingerprintKey: SyncTestHelpers.fingerprintA.canonicalKey
        )
        let state = await service.fileAvailability(
            for: SyncTestHelpers.fingerprintA.canonicalKey
        )
        #expect(state == .queuedDownload)
    }

    // MARK: - Empty/Edge inputs

    @Test func syncMetadataWithEmptyKeyStillWorks() async {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.sync, value: true)
        let service = SyncService(featureFlags: flags)
        let result = await service.syncMetadata(for: "")
        #expect(result == .success)
    }
}
