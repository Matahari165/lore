import SwiftUI

struct AISettingsView: View {
    @Bindable var model: AIKeySettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Modèle utilisé", value: OpenAIResponsesConfiguration.model)
                    .accessibilityLabel("Modèle d’intelligence artificielle")
                    .accessibilityValue(OpenAIResponsesConfiguration.model)
            }

            Section {
                LabeledContent("État") {
                    Label(
                        model.isConfigured ? "Configurée" : "Non configurée",
                        systemImage: model.isConfigured ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(model.isConfigured ? .green : .secondary)
                }

                SecureField("Clé API OpenAI", text: $model.draftKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()

                Button("Enregistrer") {
                    model.save()
                }
                .disabled(!model.canSave)

                if model.isConfigured {
                    Button("Supprimer la clé", role: .destructive) {
                        model.remove()
                    }
                }

                if let message = model.confirmationMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Clé API")
            } footer: {
                Text("Pour une explication, Lore envoie le passage et un contexte limité autour. Pour le résumé quotidien et la discussion, il peut envoyer jusqu’à 45 000 caractères (≈15 pages) de la portion lue. La clé reste dans le trousseau sécurisé de cet iPhone.")
            }
        }
        .navigationTitle("Intelligence artificielle")
        .navigationBarTitleDisplayMode(.inline)
    }
}
