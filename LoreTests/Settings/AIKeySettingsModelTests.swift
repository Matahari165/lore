import Foundation
import Testing
@testable import Lore

@MainActor
struct AIKeySettingsModelTests {
    @Test func reflectsAnExistingKeyWithoutExposingIt() {
        let store = MemoryAPIKeyStore(key: "existing-secret")
        let model = AIKeySettingsModel(keyStore: store)

        #expect(model.isConfigured)
        #expect(model.draftKey.isEmpty)
    }

    @Test func savesAndClearsTheVisibleDraft() {
        let store = MemoryAPIKeyStore()
        let model = AIKeySettingsModel(keyStore: store)
        model.draftKey = "  sk-test  "

        model.save()

        #expect(store.key == "  sk-test  ")
        #expect(model.draftKey.isEmpty)
        #expect(model.isConfigured)
        #expect(model.errorMessage == nil)
    }

    @Test func removesAConfiguredKey() {
        let store = MemoryAPIKeyStore(key: "secret")
        let model = AIKeySettingsModel(keyStore: store)

        model.remove()

        #expect(store.key == nil)
        #expect(!model.isConfigured)
    }

    @Test func exposesStorageFailureWithoutClaimingSuccess() {
        let model = AIKeySettingsModel(keyStore: FailingAPIKeyStore())
        model.draftKey = "secret"

        model.save()

        #expect(!model.isConfigured)
        #expect(model.errorMessage == "Trousseau indisponible")
        #expect(model.confirmationMessage == nil)
    }
}

private final class MemoryAPIKeyStore: OpenAIAPIKeyStore, @unchecked Sendable {
    var key: String?
    init(key: String? = nil) { self.key = key }
    func loadAPIKey() throws -> String? { key }
    func saveAPIKey(_ key: String?) throws { self.key = key }
}

private struct FailingAPIKeyStore: OpenAIAPIKeyStore {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Trousseau indisponible" }
    }
    func loadAPIKey() throws -> String? { nil }
    func saveAPIKey(_ key: String?) throws { throw Failure() }
}
