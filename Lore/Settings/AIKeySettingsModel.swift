import Foundation
import Observation

@MainActor
@Observable
final class AIKeySettingsModel {
    private let keyStore: any OpenAIAPIKeyStore

    var draftKey = ""
    private(set) var isConfigured = false
    private(set) var errorMessage: String?
    private(set) var confirmationMessage: String?

    init(keyStore: any OpenAIAPIKeyStore = KeychainOpenAIAPIKeyStore()) {
        self.keyStore = keyStore
        refresh()
    }

    var canSave: Bool {
        !draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() {
        guard canSave else {
            errorMessage = "Saisis une clé API avant de l’enregistrer."
            confirmationMessage = nil
            return
        }
        do {
            try keyStore.saveAPIKey(draftKey)
            draftKey = ""
            isConfigured = true
            errorMessage = nil
            confirmationMessage = "Clé enregistrée dans le trousseau sécurisé de l’iPhone."
        } catch {
            errorMessage = error.localizedDescription
            confirmationMessage = nil
        }
    }

    func remove() {
        do {
            try keyStore.saveAPIKey(nil)
            draftKey = ""
            isConfigured = false
            errorMessage = nil
            confirmationMessage = "Clé supprimée."
        } catch {
            errorMessage = error.localizedDescription
            confirmationMessage = nil
        }
    }

    private func refresh() {
        do {
            let key = try keyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines)
            isConfigured = !(key?.isEmpty ?? true)
            errorMessage = nil
        } catch {
            isConfigured = false
            errorMessage = error.localizedDescription
        }
    }
}
