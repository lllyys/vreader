// Purpose: Tests for KeychainService — CRUD operations, deviceId management, error handling.
// Note: These tests use the real Keychain in the test host (iOS Simulator).
// Each test uses a unique service+account to avoid cross-test pollution.

import Testing
import Foundation
@testable import vreader

@Suite("KeychainService")
struct KeychainServiceTests {

    /// Creates a KeychainService with a unique test-scoped service identifier.
    private func makeService() -> KeychainService {
        let serviceId = "com.vreader.test.\(UUID().uuidString)"
        return KeychainService(serviceIdentifier: serviceId)
    }

    // Note: Keychain cleanup in tests uses try? because cleanup failures should not
    // mask the actual test result, and each test uses a unique service identifier
    // preventing cross-test pollution.

    // MARK: - Save and Read String

    @Test func saveAndReadString() throws {
        let service = makeService()
        try service.saveString("my-secret", forAccount: "api-key")
        let result = try service.readString(forAccount: "api-key")
        #expect(result == "my-secret")
        // cleanup
        try? service.delete(forAccount: "api-key")
    }

    @Test func readNonexistentReturnsNil() throws {
        let service = makeService()
        let result = try service.readString(forAccount: "nonexistent")
        #expect(result == nil)
    }

    // MARK: - Save and Read Data

    @Test func saveAndReadData() throws {
        let service = makeService()
        let data = Data([0x00, 0x01, 0x02, 0xFF])
        try service.saveData(data, forAccount: "binary-key")
        let result = try service.readData(forAccount: "binary-key")
        #expect(result == data)
        try? service.delete(forAccount: "binary-key")
    }

    // MARK: - Update (Overwrite)

    @Test func saveOverwritesExistingValue() throws {
        let service = makeService()
        try service.saveString("value-1", forAccount: "key")
        try service.saveString("value-2", forAccount: "key")
        let result = try service.readString(forAccount: "key")
        #expect(result == "value-2")
        try? service.delete(forAccount: "key")
    }

    // MARK: - Delete

    @Test func deleteExistingItem() throws {
        let service = makeService()
        try service.saveString("to-delete", forAccount: "key")
        try service.delete(forAccount: "key")
        let result = try service.readString(forAccount: "key")
        #expect(result == nil)
    }

    @Test func deleteNonexistentDoesNotThrow() throws {
        let service = makeService()
        // Should not throw — deleting something that does not exist is a no-op
        try service.delete(forAccount: "nonexistent")
    }

    // MARK: - Edge Cases: Empty String

    @Test func saveEmptyString() throws {
        let service = makeService()
        try service.saveString("", forAccount: "empty")
        let result = try service.readString(forAccount: "empty")
        #expect(result == "")
        try? service.delete(forAccount: "empty")
    }

    // MARK: - Edge Cases: Long Values

    @Test func saveLongValue() throws {
        let service = makeService()
        let longString = String(repeating: "A", count: 4096)
        try service.saveString(longString, forAccount: "long")
        let result = try service.readString(forAccount: "long")
        #expect(result == longString)
        try? service.delete(forAccount: "long")
    }

    // MARK: - Edge Cases: Special Characters

    @Test func saveSpecialCharacters() throws {
        let service = makeService()
        let special = "p@$$w0rd!#%^&*()_+-=[]{}|;':\",./<>?"
        try service.saveString(special, forAccount: "special")
        let result = try service.readString(forAccount: "special")
        #expect(result == special)
        try? service.delete(forAccount: "special")
    }

    // MARK: - Edge Cases: Unicode / CJK

    @Test func saveUnicodeValue() throws {
        let service = makeService()
        let unicode = "测试密钥🔑日本語한국어"
        try service.saveString(unicode, forAccount: "unicode")
        let result = try service.readString(forAccount: "unicode")
        #expect(result == unicode)
        try? service.delete(forAccount: "unicode")
    }

    @Test func unicodeAccountName() throws {
        let service = makeService()
        try service.saveString("value", forAccount: "账户名")
        let result = try service.readString(forAccount: "账户名")
        #expect(result == "value")
        try? service.delete(forAccount: "账户名")
    }

    // MARK: - Edge Cases: Empty Data

    @Test func saveEmptyData() throws {
        let service = makeService()
        try service.saveData(Data(), forAccount: "empty-data")
        let result = try service.readData(forAccount: "empty-data")
        #expect(result == Data())
        try? service.delete(forAccount: "empty-data")
    }

    // MARK: - Multiple Accounts

    @Test func multipleAccountsIndependent() throws {
        let service = makeService()
        try service.saveString("value-a", forAccount: "account-a")
        try service.saveString("value-b", forAccount: "account-b")
        #expect(try service.readString(forAccount: "account-a") == "value-a")
        #expect(try service.readString(forAccount: "account-b") == "value-b")
        // Deleting one does not affect the other
        try service.delete(forAccount: "account-a")
        #expect(try service.readString(forAccount: "account-a") == nil)
        #expect(try service.readString(forAccount: "account-b") == "value-b")
        try? service.delete(forAccount: "account-b")
    }

    // MARK: - DeviceId

    @Test func deviceIdGeneratedOnFirstAccess() throws {
        let service = makeService()
        let deviceId = try service.deviceId()
        #expect(!deviceId.isEmpty)
        // Should be a valid UUID
        #expect(UUID(uuidString: deviceId) != nil)
        // cleanup
        try? service.resetDeviceId()
    }

    @Test func deviceIdPersistsAcrossCalls() throws {
        let service = makeService()
        let id1 = try service.deviceId()
        let id2 = try service.deviceId()
        #expect(id1 == id2)
        try? service.resetDeviceId()
    }

    @Test func deviceIdPersistsAcrossInstances() throws {
        let serviceId = "com.vreader.test.\(UUID().uuidString)"
        let service1 = KeychainService(serviceIdentifier: serviceId)
        let id1 = try service1.deviceId()

        let service2 = KeychainService(serviceIdentifier: serviceId)
        let id2 = try service2.deviceId()
        #expect(id1 == id2)
        try? service1.resetDeviceId()
    }

    @Test func resetDeviceIdGeneratesNewId() throws {
        let service = makeService()
        let id1 = try service.deviceId()
        try service.resetDeviceId()
        let id2 = try service.deviceId()
        #expect(id1 != id2)
        #expect(UUID(uuidString: id2) != nil)
        try? service.resetDeviceId()
    }

    // MARK: - DeviceId Concurrency

    @Test func deviceIdConcurrentAccessReturnsSameId() async throws {
        let service = makeService()
        defer { try? service.resetDeviceId() }

        // Launch multiple concurrent tasks all calling deviceId()
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try service.deviceId()
                }
            }
            var results: [String] = []
            for try await id in group {
                results.append(id)
            }
            return results
        }

        // All callers must get the same persisted ID
        let uniqueIds = Set(ids)
        #expect(uniqueIds.count == 1, "All concurrent callers should get the same deviceId, got \(uniqueIds.count) unique IDs")
        #expect(UUID(uuidString: ids.first!) != nil)
    }

    // MARK: - KeychainError

    @Test func keychainErrorHasDescription() {
        let error = KeychainError.unexpectedStatus(errSecAuthFailed)
        #expect(!error.localizedDescription.isEmpty)
    }

    @Test func keychainErrorEncodingFailure() {
        let error = KeychainError.dataEncodingFailed
        #expect(!error.localizedDescription.isEmpty)
    }

    // MARK: - Sendable

    @Test func keychainServiceIsSendable() {
        let service: any Sendable = makeService()
        #expect(service is KeychainService)
    }

    @Test func keychainErrorIsSendable() {
        let error: any Sendable = KeychainError.dataEncodingFailed
        #expect(error is KeychainError)
    }
}
