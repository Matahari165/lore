import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: DailyReadingGoalModel
    @State private var aiKeyModel = AIKeySettingsModel()

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
        }
    }
}
