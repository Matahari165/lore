import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: DailyReadingGoalModel
    var onClearToday: () throws -> Int = { 0 }
    @State private var aiKeyModel = AIKeySettingsModel()
    @State private var confirmsClearToday = false
    @State private var clearTodayMessage: String?
    @State private var clearTodayError: String?
    @State private var readingFocusEnabled = ReadingFocusMode.shared.isEnabled
    @State private var showsReadingFocusGuide = false
    @State private var ttsPreferences = ReaderTTSPreferences()
    @State private var frenchVoices: [AVSpeechSynthesisVoice] = []
    @State private var englishVoices: [AVSpeechSynthesisVoice] = []
    @State private var selectedFrenchVoiceID: String = ""
    @State private var selectedEnglishVoiceID: String = ""

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
                    Toggle("Réduire les interruptions", isOn: $readingFocusEnabled)
                        .onChange(of: readingFocusEnabled) { _, isEnabled in
                            ReadingFocusMode.shared.setEnabled(isEnabled)
                        }

                    Button("Configurer Concentration sur l’iPhone", systemImage: "moon.zzz") {
                        showsReadingFocusGuide = true
                    }
                } header: {
                    Text("Mode Lecture")
                } footer: {
                    Text("Facultatif. Lore masque ses propres bannières et sons pendant la lecture. Pour les autres apps, configurez Concentration sur l’iPhone.")
                }

                Section {
                    Stepper(value: Binding(
                        get: { Double(ttsPreferences.speechRate) },
                        set: { ttsPreferences.speechRate = Float($0) }
                    ), in: 0.5...2.0, step: 0.25) {
                        LabeledContent("Vitesse", value: ttsPreferences.speechRateLabel)
                    }

                    if !frenchVoices.isEmpty {
                        Picker("Voix française", selection: $selectedFrenchVoiceID) {
                            ForEach(frenchVoices, id: \.identifier) { voice in
                                Text(voiceLabel(for: voice)).tag(voice.identifier)
                            }
                        }
                        .onChange(of: selectedFrenchVoiceID) { _, newID in
                            ttsPreferences.setPreferredVoiceIdentifier(newID, forLanguage: "fr")
                        }
                    }

                    if !englishVoices.isEmpty {
                        Picker("Voix anglaise", selection: $selectedEnglishVoiceID) {
                            ForEach(englishVoices, id: \.identifier) { voice in
                                Text(voiceLabel(for: voice)).tag(voice.identifier)
                            }
                        }
                        .onChange(of: selectedEnglishVoiceID) { _, newID in
                            ttsPreferences.setPreferredVoiceIdentifier(newID, forLanguage: "en")
                        }
                    }
                } header: {
                    Text("Lecture audio (TTS)")
                } footer: {
                    Text("100 % local. Lore privilégie automatiquement les voix Premium et Améliorées. Pour télécharger des voix Apple plus naturelles : Réglages iPhone > Accessibilité > Contenu énoncé > Voix.")
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
                    LabeledContent("Modèle utilisé", value: OpenAIResponsesConfiguration.model)
                        .accessibilityLabel("Modèle d’intelligence artificielle")
                        .accessibilityValue(OpenAIResponsesConfiguration.model)

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
                    Text("Pour une explication, Lore envoie le passage et un contexte limité autour. Pour le résumé quotidien et la discussion, il peut envoyer jusqu’à 45 000 caractères (≈15 pages) de la portion lue. La clé reste dans le trousseau sécurisé de cet iPhone.")
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
            .sheet(isPresented: $showsReadingFocusGuide) {
                ReadingFocusGuideView()
            }
            .onAppear {
                loadTTSVoices()
            }
        }
    }

    private func loadTTSVoices() {
        frenchVoices = ttsPreferences.availableSystemVoices(forLanguage: "fr")
        englishVoices = ttsPreferences.availableSystemVoices(forLanguage: "en")
        selectedFrenchVoiceID = ttsPreferences.preferredVoiceIdentifier(forLanguage: "fr")
            ?? ttsPreferences.bestVoice(forLanguage: "fr")?.identifier
            ?? ""
        selectedEnglishVoiceID = ttsPreferences.preferredVoiceIdentifier(forLanguage: "en")
            ?? ttsPreferences.bestVoice(forLanguage: "en")?.identifier
            ?? ""
    }

    private func voiceLabel(for voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        #if swift(>=5.7)
        if voice.quality == .premium {
            quality = "Premium"
        } else if voice.quality == .enhanced {
            quality = "Améliorée"
        } else {
            quality = "Standard"
        }
        #else
        if voice.quality == .enhanced {
            quality = "Améliorée"
        } else {
            quality = "Standard"
        }
        #endif
        return "\(voice.name) (\(quality))"
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

private struct ReadingFocusGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("À faire une seule fois") {
                    ForEach(ReadingFocusGuide.steps) { step in
                        HStack(alignment: .top, spacing: 14) {
                            Text(step.id, format: .number)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(LoreTheme.ink, in: Circle())
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title)
                                    .font(.body.weight(.semibold))
                                Text(step.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    Label(ReadingFocusGuide.limitation, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Concentration sur l’iPhone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
