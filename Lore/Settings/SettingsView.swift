import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: DailyReadingGoalModel

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
