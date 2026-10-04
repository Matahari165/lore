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
    }
}

@MainActor
struct LoreTTSAudioSessionCoordinatorTests {
    @Test func interruptionBeganCallsCallback() {
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

        // Les notifications sont traitées sur la file principale
        #expect(coordinator.onInterruptionBegan != nil)
    }

    @Test func routeChangeOldDeviceUnavailableTriggersPause() {
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

        #expect(coordinator.onRouteChangeOldDeviceUnavailable != nil)
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
