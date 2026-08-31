import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: DailyReadingGoalModel
    var onClearToday: () throws -> Int = { 0 }
    @State private var aiKeyModel = AIKeySettingsModel()
    @State private var confirmsClearToday = false
    @State private var clearTodayMessage: String?
    @State private var clearTodayError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Objectif quotidien", isOn: Binding(
                        get: { model.isEnabled },
                        set: { model.setEnabled($0) }
                    ))

                    if let minutes = model.minutes {
                        Stepper(value: Binding(
                            get: { minutes },
                            set: { model.setMinutes($0) }
                        ), in: DailyReadingGoal.allowedMinutes, step: 5) {
                            LabeledContent("Durée", value: "\(minutes) min")
                        }
                        .accessibilityValue("\(minutes) minutes")
                    }
                } header: {
                    Text("Lecture")
                } footer: {
                    Text("La progression utilise uniquement vos sessions de lecture enregistrées sur cet appareil.")
                }

                if let message = model.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Données de lecture") {
                    Button("Effacer les sessions d’aujourd’hui", systemImage: "trash", role: .destructive) {
                        confirmsClearToday = true
                    }
                    if let clearTodayMessage {
                        Label(clearTodayMessage, systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isSummaryElement)
                    }
                    if let clearTodayError {
                        Label(clearTodayError, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent("État") {
                        Label(
                            aiKeyModel.isConfigured ? "Configurée" : "Non configurée",
                            systemImage: aiKeyModel.isConfigured ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(aiKeyModel.isConfigured ? .green : .secondary)
                    }

                    SecureField("Clé API OpenAI", text: $aiKeyModel.draftKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()

                    Button("Enregistrer") {
                        aiKeyModel.save()
                    }
                    .disabled(!aiKeyModel.canSave)

                    if aiKeyModel.isConfigured {
                        Button("Supprimer la clé", role: .destructive) {
                            aiKeyModel.remove()
                        }
                    }

                    if let message = aiKeyModel.confirmationMessage {
                        Label(message, systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let message = aiKeyModel.errorMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Intelligence artificielle")
                } footer: {
                    Text("Pour une explication, Lore envoie le passage et un contexte limité autour. Pour le résumé quotidien, il peut envoyer jusqu’à 18 000 caractères de la portion lue la veille. La clé reste dans le trousseau sécurisé de cet iPhone.")
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .confirmationDialog(
                "Effacer les sessions d’aujourd’hui ?",
                isPresented: $confirmsClearToday,
                titleVisibility: .visible
            ) {
                Button("Effacer aujourd’hui", role: .destructive, action: clearToday)
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Seul le temps de lecture du jour local sera supprimé. Les autres jours et les livres restent intacts.")
            }
        }
    }

    private func clearToday() {
        do {
            let count = try onClearToday()
            clearTodayMessage = count == 0
                ? "Aucune session à effacer aujourd’hui."
                : "Les sessions d’aujourd’hui ont été effacées."
            clearTodayError = nil
        } catch {
            clearTodayMessage = nil
            clearTodayError = error.localizedDescription
        }
    }
}
