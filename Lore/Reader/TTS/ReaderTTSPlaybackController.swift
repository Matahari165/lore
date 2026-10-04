import AVFoundation
import Foundation
import MediaPlayer
import Observation
import ReadiumNavigator
import ReadiumShared
import UIKit

/// Contrôleur de lecture audio locale (TTS) pour un livre ouvert dans Lore.
///
/// Orchestre `PublicationSpeechSynthesizer`, la session audio en arrière-plan,
/// les commandes de l'écran verrouillé (`MPNowPlayingInfoCenter` et `MPRemoteCommandCenter`)
/// et la synchronisation de position avec le lecteur Readium.
@MainActor
@Observable
final class ReaderTTSPlaybackController: NSObject, PublicationSpeechSynthesizerDelegate, AVTTSEngineDelegate {
    let bookID: UUID
    let bookTitle: String
    let bookAuthor: String?
    let coverData: Data?

    let preferences: ReaderTTSPreferences
    let audioCoordinator: LoreTTSAudioSessionCoordinator

    private(set) var synthesizer: PublicationSpeechSynthesizer?
    private(set) var isPlaying: Bool = false
    private(set) var isSpeaking: Bool = false
    private(set) var currentUtterance: PublicationSpeechSynthesizer.Utterance?
    private(set) var currentLocator: Locator?
    private(set) var playbackRate: Float = 1.0
    private(set) var selectedVoiceName: String?
    var errorMessage: String?

    var onLocationUpdate: (@MainActor (Locator) -> Void)?
    var onProgressRecord: (@MainActor (Locator) -> Void)?
    var onStop: (@MainActor (Locator?) -> Void)?
    var onStateChange: (@MainActor () -> Void)?

    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private nonisolated(unsafe) var currentVoice: AVSpeechSynthesisVoice?
    private nonisolated(unsafe) var currentPlaybackRate: Float = 1.0

    init(
        publication: Publication,
        bookID: UUID,
        bookTitle: String,
        bookAuthor: String?,
        coverData: Data?,
        preferences: ReaderTTSPreferences = ReaderTTSPreferences()
    ) {
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.coverData = coverData
        self.preferences = preferences
        let coordinator = LoreTTSAudioSessionCoordinator()
        self.audioCoordinator = coordinator
        self.playbackRate = preferences.speechRate
        self.currentPlaybackRate = preferences.speechRate

        super.init()

        configureCoordinator()
        setupSynthesizer(for: publication)
    }

    // MARK: - Initialisation du synthétiseur

    private func setupSynthesizer(for publication: Publication) {
        let bookLanguage = publication.metadata.language?.code.bcp47 ?? "fr"
        let bestVoice = preferences.bestVoice(forLanguage: bookLanguage)
        self.currentVoice = bestVoice
        self.selectedVoiceName = bestVoice?.name

        var config = PublicationSpeechSynthesizer.Configuration()
        if let bestVoice {
            config.voiceIdentifier = bestVoice.identifier
            config.defaultLanguage = Language(code: .bcp47(bestVoice.language))
        }

        self.synthesizer = PublicationSpeechSynthesizer(
            publication: publication,
            config: config,
            audioSession: audioCoordinator,
            engineFactory: { [weak self] in
                AVTTSEngine(delegate: self)
            },
            delegate: self
        )
    }

    private func configureCoordinator() {
        audioCoordinator.onInterruptionBegan = { [weak self] in
            self?.pause()
        }
        audioCoordinator.onInterruptionEnded = { [weak self] shouldResume in
            if shouldResume {
                self?.resume()
            }
        }
        audioCoordinator.onRouteChangeOldDeviceUnavailable = { [weak self] in
            self?.pause()
        }
    }

    // MARK: - Commandes de lecture

    func start(from locator: Locator?) {
        guard let synthesizer else {
            errorMessage = "La synthèse vocale n'est pas disponible pour ce livre."
            return
        }
        currentLocator = locator
        audioCoordinator.activateSession()
        setupRemoteCommands()
        isPlaying = true
        isSpeaking = true
        updateNowPlaying()
        onStateChange?()
        synthesizer.start(from: locator)
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        synthesizer?.pause()
        isPlaying = false
        isSpeaking = false
        updateNowPlaying()
        onStateChange?()
        if let currentLocator {
            onProgressRecord?(currentLocator)
        }
    }

    func resume() {
        audioCoordinator.activateSession()
        isPlaying = true
        isSpeaking = true
        updateNowPlaying()
        onStateChange?()
        synthesizer?.resume()
    }

    func stop() {
        synthesizer?.stop()
        isPlaying = false
        isSpeaking = false
        updateNowPlaying()
        onStateChange?()
        if let currentLocator {
            onStop?(currentLocator)
        }
    }

    func previous() {
        synthesizer?.previous()
    }

    func next() {
        synthesizer?.next()
    }

    func cyclePlaybackRate() {
        playbackRate = preferences.cycleSpeechRate()
        currentPlaybackRate = playbackRate
        updateNowPlaying()
    }

    var playbackRateLabel: String {
        preferences.speechRateLabel
    }

    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        currentVoice = voice
        selectedVoiceName = voice.name
        preferences.setPreferredVoiceIdentifier(voice.identifier, forLanguage: voice.language)
        synthesizer?.config.voiceIdentifier = voice.identifier
    }

    // MARK: - PublicationSpeechSynthesizerDelegate

    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        stateDidChange state: PublicationSpeechSynthesizer.State
    ) {
        switch state {
        case .stopped:
            isPlaying = false
            isSpeaking = false
            updateNowPlaying()
            onStateChange?()
            if let currentLocator {
                onStop?(currentLocator)
            }
        case let .playing(utterance, range: wordRange):
            isPlaying = true
            isSpeaking = true
            currentUtterance = utterance
            let activeLoc = wordRange ?? utterance.locator
            currentLocator = activeLoc
            onLocationUpdate?(activeLoc)
            onProgressRecord?(activeLoc)
            updateNowPlaying()
            onStateChange?()
        case let .paused(utterance):
            isPlaying = false
            isSpeaking = false
            currentUtterance = utterance
            currentLocator = utterance.locator
            onLocationUpdate?(utterance.locator)
            onProgressRecord?(utterance.locator)
            updateNowPlaying()
            onStateChange?()
        }
    }

    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        utterance: PublicationSpeechSynthesizer.Utterance,
        didFailWithError error: PublicationSpeechSynthesizer.Error
    ) {
        errorMessage = "Erreur de lecture vocale : \(error.localizedDescription)"
        isPlaying = false
        isSpeaking = false
        updateNowPlaying()
        onStateChange?()
    }

    // MARK: - AVTTSEngineDelegate

    nonisolated func avTTSEngine(_ engine: AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
        let baseRate = AVSpeechUtteranceDefaultSpeechRate
        let targetRate = baseRate * currentPlaybackRate
        utterance.rate = min(max(targetRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        if let voice = currentVoice {
            utterance.voice = voice
        }
    }

    // MARK: - Écran verrouillé & Now Playing

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: bookTitle,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
        ]
        if let bookAuthor, !bookAuthor.isEmpty {
            info[MPMediaItemPropertyArtist] = bookAuthor
        }
        if let coverData,
           let image = UIImage(data: coverData),
           image.size.width > 0,
           image.size.height > 0 {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        if let totalProgression = currentLocator?.locations.totalProgression,
           !totalProgression.isNaN,
           !totalProgression.isInfinite,
           totalProgression >= 0 {
            // Représentation de progression relative de 0 à 1000
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = totalProgression * 1000.0
            info[MPMediaItemPropertyPlaybackDuration] = 1000.0
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        guard remoteTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]

        remoteTargets = [
            (center.playCommand, center.playCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.resume() }
                return .success
            }),
            (center.pauseCommand, center.pauseCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.pause() }
                return .success
            }),
            (center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.togglePlayback() }
                return .success
            }),
            (center.previousTrackCommand, center.previousTrackCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.previous() }
                return .success
            }),
            (center.nextTrackCommand, center.nextTrackCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.next() }
                return .success
            }),
            (center.skipBackwardCommand, center.skipBackwardCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.previous() }
                return .success
            }),
            (center.skipForwardCommand, center.skipForwardCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.next() }
                return .success
            }),
        ]
    }

    func teardown() {
        synthesizer?.stop()
        isPlaying = false
        isSpeaking = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        for (command, token) in remoteTargets {
            command.removeTarget(token)
        }
        remoteTargets = []
        audioCoordinator.deactivateSession()
    }
}
