import AVFoundation
import Foundation
import ReadiumShared

/// Préférences de synthèse vocale pour le lecteur Lore.
///
/// Les préférences gèrent la vitesse de lecture et la sélection automatique
/// ou manuelle de la meilleure voix disponible sur l'appareil (en privilégiant
/// les voix Premium de Siri et les voix Améliorées pour le français et l'anglais).
@MainActor
final class ReaderTTSPreferences {
    static let availableRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    static let defaultRate: Float = 1.0

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Vitesse de lecture

    var speechRate: Float {
        get {
            let saved = userDefaults.float(forKey: Keys.speechRate)
            return saved > 0 ? saved : Self.defaultRate
        }
        set {
            userDefaults.set(newValue, forKey: Keys.speechRate)
        }
    }

    func cycleSpeechRate() -> Float {
        let current = speechRate
        let index = Self.availableRates.firstIndex { abs($0 - current) < 0.05 } ?? 1
        let nextIndex = (index + 1) % Self.availableRates.count
        let nextRate = Self.availableRates[nextIndex]
        speechRate = nextRate
        return nextRate
    }

    var speechRateLabel: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        let formatted = formatter.string(from: NSNumber(value: speechRate)) ?? "\(speechRate)"
        return "\(formatted)×"
    }

    // MARK: - Sélection de voix

    func preferredVoiceIdentifier(forLanguage languageCode: String) -> String? {
        let langKey = languageKey(from: languageCode)
        return userDefaults.string(forKey: Keys.voiceIdentifierPrefix + langKey)
    }

    func setPreferredVoiceIdentifier(_ identifier: String?, forLanguage languageCode: String) {
        let langKey = languageKey(from: languageCode)
        let key = Keys.voiceIdentifierPrefix + langKey
        if let identifier {
            userDefaults.set(identifier, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    /// Voix disponibles sur l'iPhone pour la langue donnée (sans doublons super-compacts).
    func availableSystemVoices(forLanguage languageCode: String?) -> [AVSpeechSynthesisVoice] {
        let targetLanguage = languageKey(from: languageCode ?? "fr")
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                if #available(iOS 17.0, *) {
                    if voice.voiceTraits.contains(.isNoveltyVoice) || voice.voiceTraits.contains(.isPersonalVoice) {
                        return false
                    }
                }
                guard !voice.identifier.contains(".eloquence.") else { return false }
                guard !voice.identifier.contains(".super-compact.") else { return false }

                let voiceLang = languageKey(from: voice.language)
                return voiceLang.caseInsensitiveCompare(targetLanguage) == .orderedSame
            }
            .sorted { v1, v2 in
                // Tri : Premium > Enhanced > Default, puis par nom
                let q1 = qualityRank(v1.quality)
                let q2 = qualityRank(v2.quality)
                if q1 != q2 { return q1 > q2 }
                return v1.name.localizedCaseInsensitiveCompare(v2.name) == .orderedAscending
            }
    }

    /// Choisit intelligemment la meilleure voix pour la langue :
    /// 1. La voix explicitement mémorisée par l'utilisateur si elle est installée.
    /// 2. La meilleure voix installée disponible (Premium > Enhanced > Standard).
    /// 3. À défaut, la voix système native par défaut pour la langue cible.
    func bestVoice(forLanguage languageCode: String?) -> AVSpeechSynthesisVoice? {
        let targetLang = languageKey(from: languageCode ?? "fr")
        let voices = availableSystemVoices(forLanguage: targetLang)

        // 1. Voix explicitement configurée par l'utilisateur
        if let preferredID = preferredVoiceIdentifier(forLanguage: targetLang),
           let matching = voices.first(where: { $0.identifier == preferredID }) {
            return matching
        }

        // 2. Meilleure voix système disponible parmi les voix installées
        if let bestAvailable = voices.first {
            return bestAvailable
        }

        // 3. Repli système par défaut pour la langue
        let defaultLocale: String
        switch targetLang {
        case "en": defaultLocale = "en-US"
        case "fr": defaultLocale = "fr-FR"
        case "es": defaultLocale = "es-ES"
        case "de": defaultLocale = "de-DE"
        case "it": defaultLocale = "it-IT"
        default: defaultLocale = "\(targetLang)-\(targetLang.uppercased())"
        }

        return AVSpeechSynthesisVoice(language: defaultLocale)
            ?? AVSpeechSynthesisVoice(language: "fr-FR")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Formate un libellé clair pour l'affichage de la voix dans l'interface (nom, région et qualité).
    func displayLabel(for voice: AVSpeechSynthesisVoice) -> String {
        let isSiri = voice.identifier.contains(".siri.") || voice.identifier.contains(".gryphon-neural_")
        let quality: String
        if isSiri {
            quality = "Siri"
        } else if voice.quality == .premium {
            quality = "Premium"
        } else if voice.quality == .enhanced {
            quality = "Améliorée"
        } else {
            quality = "Standard"
        }

        let region = Locale.current.localizedString(forRegionCode: String(voice.language.suffix(2)))
        let regionSuffix = region.map { " — \($0)" } ?? ""

        return "\(voice.name)\(regionSuffix) (\(quality))"
    }

    // MARK: - Utilitaires internes

    private func languageKey(from raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.hasPrefix("fr") { return "fr" }
        if cleaned.hasPrefix("en") { return "en" }
        return String(cleaned.prefix(2))
    }

    private func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        #if swift(>=5.7)
        if quality == .premium { return 3 }
        #endif
        if quality == .enhanced { return 2 }
        return 1
    }

    private enum Keys {
        static let speechRate = "lore.reader.tts.speechRate"
        static let voiceIdentifierPrefix = "lore.reader.tts.voice."
    }
}
