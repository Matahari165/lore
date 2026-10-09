import AVFAudio
import Foundation
import ReadiumShared
import Testing
@testable import Lore

@MainActor
struct ReaderTTSPreferencesTests {
    @Test func defaultSpeechRateIsOne() {
        let defaults = UserDefaults(suiteName: "ReaderTTSPreferencesTests_default")!
        defaults.removePersistentDomain(forName: "ReaderTTSPreferencesTests_default")
        let prefs = ReaderTTSPreferences(userDefaults: defaults)

        #expect(prefs.speechRate == 1.0)
        #expect(prefs.speechRateLabel == "1×")
    }

    @Test func speechRateCyclesThroughAvailableRates() {
        let defaults = UserDefaults(suiteName: "ReaderTTSPreferencesTests_cycle")!
        defaults.removePersistentDomain(forName: "ReaderTTSPreferencesTests_cycle")
        let prefs = ReaderTTSPreferences(userDefaults: defaults)

        let initialRate = prefs.speechRate
        let nextRate = prefs.cycleSpeechRate()
        #expect(nextRate != initialRate)
        #expect(prefs.speechRate == nextRate)

        // Sauvegardé dans UserDefaults
        let reloaded = ReaderTTSPreferences(userDefaults: defaults)
        #expect(reloaded.speechRate == nextRate)
    }

    @Test func preferredVoiceIdentifierIsStoredPerLanguage() {
        let defaults = UserDefaults(suiteName: "ReaderTTSPreferencesTests_voice")!
        defaults.removePersistentDomain(forName: "ReaderTTSPreferencesTests_voice")
        let prefs = ReaderTTSPreferences(userDefaults: defaults)

        prefs.setPreferredVoiceIdentifier("com.apple.voice.thomas.fr", forLanguage: "fr")
        prefs.setPreferredVoiceIdentifier("com.apple.voice.samantha.en", forLanguage: "en")

        #expect(prefs.preferredVoiceIdentifier(forLanguage: "fr") == "com.apple.voice.thomas.fr")
        #expect(prefs.preferredVoiceIdentifier(forLanguage: "fr-FR") == "com.apple.voice.thomas.fr")
        #expect(prefs.preferredVoiceIdentifier(forLanguage: "en") == "com.apple.voice.samantha.en")
        #expect(prefs.preferredVoiceIdentifier(forLanguage: "en-US") == "com.apple.voice.samantha.en")
    }

    @Test func bestVoiceReturnsSystemVoiceForFrenchAndEnglish() {
        let defaults = UserDefaults(suiteName: "ReaderTTSPreferencesTests_best")!
        defaults.removePersistentDomain(forName: "ReaderTTSPreferencesTests_best")
        let prefs = ReaderTTSPreferences(userDefaults: defaults)

        let frVoice = prefs.bestVoice(forLanguage: "fr")
        #expect(frVoice != nil)

        let enVoice = prefs.bestVoice(forLanguage: "en")
        #expect(enVoice != nil)

        // Les voix système françaises et anglaises ne sont plus filtrées à tort
        let systemFrVoices = prefs.availableSystemVoices(forLanguage: "fr")
        #expect(!systemFrVoices.isEmpty || frVoice != nil)
    }
}

@MainActor
struct LoreChapterTextExtractorTests {
    @Test func stripHTMLRemovesTagsAndUnescapesEntities() {
        let html = """
        <html>
        <head><title>Test</title><style>p { color: red; }</style></head>
        <body>
            <h1>Chapitre Premier</h1>
            <p>Voici un premier &eacute;l&eacute;ment avec du texte.</p>
            <p>Deuxi&egrave;me paragraphe &mdash; tr&egrave;s int&eacute;ressant &amp; enrichi.</p>
        </body>
        </html>
        """
        let cleaned = LoreChapterTextExtractor.stripHTML(html)
        #expect(!cleaned.contains("<head>"))
        #expect(!cleaned.contains("<style>"))
        #expect(!cleaned.contains("<h1>"))
        #expect(!cleaned.contains("<p>"))
        #expect(cleaned.contains("Chapitre Premier"))
        #expect(cleaned.contains("premier élément"))
        #expect(cleaned.contains("Deuxième paragraphe — très intéressant & enrichi."))
    }

    @Test func segmentSentencesSplitsTextAccurately() {
        let text = "Il marchait lentement dans la nuit. Soudain, un bruit retentit ! Que se passait-il donc ? Personne ne répondit."
        let sentences = LoreChapterTextExtractor.segmentSentences(from: text, languageCode: "fr")
        #expect(sentences.count == 4)
        #expect(sentences[0].text == "Il marchait lentement dans la nuit.")
        #expect(sentences[1].text == "Soudain, un bruit retentit !")
        #expect(sentences[2].text == "Que se passait-il donc ?")
        #expect(sentences[3].text == "Personne ne répondit.")
    }

    @Test func segmentSentencesMergesDialogueIncisesAndPreservesAbbreviations() {
        let dialogue = "« Bonjour ! » dit-il en souriant. Le Dr. Martin entra alors dans la pièce."
        let sentences = LoreChapterTextExtractor.segmentSentences(from: dialogue, languageCode: "fr")
        #expect(sentences.count == 2)
        #expect(sentences[0].text.contains("dit-il en souriant"))
        #expect(sentences[1].text.contains("Dr. Martin entra"))
    }

    @Test func stripHTMLDecodesHexadecimalEntitiesAndAdjacentTags() {
        let html = "<p><span>Premier</span><span>mot</span> &#x2014; test&#x27;s &laquo;valid&raquo;.</p>"
        let cleaned = LoreChapterTextExtractor.stripHTML(html)
        #expect(cleaned.contains("Premier mot"))
        #expect(cleaned.contains("—"))
        #expect(cleaned.contains("test's"))
        #expect(cleaned.contains("«valid»"))
    }

    @Test func oversizedSentencesAreChunkedForSpeech() {
        // Texte sans ponctuation : le tokenizer + la fusion des incises
        // produiraient un seul énoncé géant, capable de bloquer le service
        // vocal et de faire tuer l'app. Le découpeur doit borner chaque morceau.
        let longText = String(repeating: "mot ", count: 2000)
        let sentences = LoreChapterTextExtractor.segmentSentences(from: longText, languageCode: "fr")
        #expect(!sentences.isEmpty)
        #expect(sentences.allSatisfy { !$0.text.isEmpty })
        #expect(sentences.allSatisfy { $0.text.count <= LoreChapterTextExtractor.maxUtteranceLength })
    }

    @Test func findStartingSentenceIndexByProgression() {
        let extractor = LoreChapterTextExtractor()
        let sentences = [
            LoreTTSSentence(chapterIndex: 0, sentenceIndex: 0, text: "A", locator: makeLocator(progression: 0.1)),
            LoreTTSSentence(chapterIndex: 0, sentenceIndex: 1, text: "B", locator: makeLocator(progression: 0.4)),
            LoreTTSSentence(chapterIndex: 0, sentenceIndex: 2, text: "C", locator: makeLocator(progression: 0.8))
        ]

        let index = extractor.findStartingSentenceIndex(in: sentences, for: makeLocator(progression: 0.42))
        #expect(index == 1)

        let indexStart = extractor.findStartingSentenceIndex(in: sentences, for: makeLocator(progression: 0.05))
        #expect(indexStart == 0)
    }

    @Test func emptyOrWhitespaceHTMLYieldsNoSentences() {
        let empty = "   \n\t  "
        let sentences = LoreChapterTextExtractor.segmentSentences(from: empty, languageCode: "fr")
        #expect(sentences.isEmpty)
    }

    private func makeLocator(progression: Double) -> Locator {
        Locator(
            href: URL(string: "chapter1.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: progression, totalProgression: progression)
        )
    }
}

@MainActor
struct LoreTTSAudioSessionCoordinatorTests {
    @Test func interruptionBeganCallsCallback() async {
        let coordinator = LoreTTSAudioSessionCoordinator()
        var beganCalled = false
        coordinator.onInterruptionBegan = {
            beganCalled = true
        }

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )

        await Task.yield()

        // Les notifications sont traitées sur la file principale
        #expect(beganCalled)
    }

    @Test func routeChangeOldDeviceUnavailableTriggersPause() async {
        let coordinator = LoreTTSAudioSessionCoordinator()
        var pauseTriggered = false
        coordinator.onRouteChangeOldDeviceUnavailable = {
            pauseTriggered = true
        }

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            ]
        )

        await Task.yield()

        #expect(pauseTriggered)
    }
}

@MainActor
struct TTSLocatorProgressTests {
    @Test func ttsProgressRecordsLocatorInPositionController() async throws {
        let store = TTSProgressStoreSpy()
        let controller = ReadingPositionController(bookID: UUID(), store: store, debounceDuration: .seconds(60))

        let testLocator = makeLocator(progression: 0.35)
        controller.record(testLocator)

        try await controller.flush()
        #expect(store.saved.count == 1)
        #expect(try store.saved.last.map { try LocatorPersistenceCodec.decode($0.stored).locator } == testLocator)
    }

    @Test func ttsStopFlushesLatestLocatorImmediately() async throws {
        let store = TTSProgressStoreSpy()
        let bookID = UUID()
        let controller = ReadingPositionController(bookID: bookID, store: store, debounceDuration: .seconds(60))

        let finishLocator = makeLocator(progression: 0.72)
        try await controller.flush(currentLocator: finishLocator)

        #expect(store.saved.count == 1)
        #expect(store.saved.first?.bookID == bookID)
        #expect(try store.saved.first.map { try LocatorPersistenceCodec.decode($0.stored).locator } == finishLocator)
    }

    private func makeLocator(progression: Double) -> Locator {
        Locator(
            href: URL(string: "chapter1.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: progression, totalProgression: progression)
        )
    }
}

@MainActor
private final class TTSProgressStoreSpy: ReaderProgressStore {
    struct Saved {
        let stored: StoredLocator
        let bookID: UUID
        let progression: Double?
    }

    private(set) var saved: [Saved] = []

    func storedLocator(for bookID: UUID) throws -> StoredLocator? {
        saved.last?.stored
    }

    func saveLocator(_ stored: StoredLocator, progression: Double?, for bookID: UUID) throws {
        saved.append(Saved(stored: stored, bookID: bookID, progression: progression))
    }
}
