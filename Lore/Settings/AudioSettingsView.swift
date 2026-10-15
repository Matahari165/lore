import AVFoundation
import SwiftUI

struct AudioSettingsView: View {
    @State private var ttsPreferences = ReaderTTSPreferences()
    @State private var frenchVoices: [AVSpeechSynthesisVoice] = []
    @State private var englishVoices: [AVSpeechSynthesisVoice] = []
    @State private var selectedFrenchVoiceID: String = ""
    @State private var selectedEnglishVoiceID: String = ""

    var body: some View {
        Form {
            Section {
                Stepper(value: Binding(
                    get: { Double(ttsPreferences.speechRate) },
                    set: { ttsPreferences.speechRate = Float($0) }
                ), in: 0.5...2.0, step: 0.25) {
                    LabeledContent("Vitesse", value: ttsPreferences.speechRateLabel)
                }
            }

            Section {
                if !frenchVoices.isEmpty {
                    Picker("Voix française", selection: $selectedFrenchVoiceID) {
                        ForEach(frenchVoices, id: \.identifier) { voice in
                            Text(ttsPreferences.displayLabel(for: voice)).tag(voice.identifier)
                        }
                    }
                    .onChange(of: selectedFrenchVoiceID) { _, newID in
                        ttsPreferences.setPreferredVoiceIdentifier(newID, forLanguage: "fr")
                    }
                } else {
                    Text("Aucune voix française détectée. La voix par défaut de l’iPhone sera utilisée.")
                        .foregroundStyle(.secondary)
                }

                if !englishVoices.isEmpty {
                    Picker("Voix anglaise", selection: $selectedEnglishVoiceID) {
                        ForEach(englishVoices, id: \.identifier) { voice in
                            Text(ttsPreferences.displayLabel(for: voice)).tag(voice.identifier)
                        }
                    }
                    .onChange(of: selectedEnglishVoiceID) { _, newID in
                        ttsPreferences.setPreferredVoiceIdentifier(newID, forLanguage: "en")
                    }
                } else {
                    Text("Aucune voix anglaise détectée. La voix par défaut de l’iPhone sera utilisée.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Voix")
            } footer: {
                Text("100 % local. Les voix Premium et Améliorées sont privilégiées. Pour en télécharger : Réglages iPhone > Accessibilité > Contenu énoncé > Voix.")
            }
        }
        .navigationTitle("Lecture audio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadVoices()
        }
    }

    private func loadVoices() {
        frenchVoices = ttsPreferences.availableSystemVoices(forLanguage: "fr")
        englishVoices = ttsPreferences.availableSystemVoices(forLanguage: "en")
        selectedFrenchVoiceID = ttsPreferences.preferredVoiceIdentifier(forLanguage: "fr")
            ?? ttsPreferences.bestVoice(forLanguage: "fr")?.identifier
            ?? ""
        selectedEnglishVoiceID = ttsPreferences.preferredVoiceIdentifier(forLanguage: "en")
            ?? ttsPreferences.bestVoice(forLanguage: "en")?.identifier
            ?? ""
    }
}
