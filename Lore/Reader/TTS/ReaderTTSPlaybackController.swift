import AVFoundation
import Foundation
import MediaPlayer
import Observation
@preconcurrency import ReadiumShared
import UIKit

/// Contrôleur de lecture audio locale (TTS) natif, robuste et ultra-rapide pour Lore.
///
/// Orchestre `AVSpeechSynthesizer` directement avec `LoreChapterTextExtractor`.
/// Garantit :
/// - Un démarrage instantané et une diction continue sans interruption entre phrases ni chapitres.
/// - Un mécanisme d'époque (`playbackEpoch`) immunisé contre les race conditions et les clics rapides.
/// - La transition automatique fluide à travers les chapitres avec cache préchargé (zéro latence inter-chapitres).
/// - La gestion bidirectionnelle des chapitres sans texte (couvertures, illustrations).
/// - La persistance immédiate de la position sur pause, interruption ou déconnexion Bluetooth/AirPods.
/// - L'intégration complète `MPNowPlayingInfoCenter` et `MPRemoteCommandCenter`.
@MainActor
@Observable
final class ReaderTTSPlaybackController: NSObject, AVSpeechSynthesizerDelegate {
    let bookID: UUID
    let bookTitle: String
    let bookAuthor: String?
    let coverData: Data?

    let preferences: ReaderTTSPreferences
    let audioCoordinator: LoreTTSAudioSessionCoordinator

    private(set) var isPlaying: Bool = false
    private(set) var isSpeaking: Bool = false
    private(set) var currentLocator: Locator?
    private(set) var playbackRate: Float = 1.0
    private(set) var selectedVoiceName: String?
    var errorMessage: String?

    var onLocationUpdate: (@MainActor (Locator) -> Void)?
    var onProgressRecord: (@MainActor (Locator) -> Void)?
    var onPause: (@MainActor (Locator) -> Void)?
    var onStop: (@MainActor (Locator?) -> Void)?
    var onStateChange: (@MainActor () -> Void)?

    private let publication: Publication
    private let textExtractor = LoreChapterTextExtractor()
    private var synthesizer: AVSpeechSynthesizer?

    private var currentChapterIndex: Int = 0
    private var sentences: [LoreTTSSentence] = []
    private var currentSentenceIndex: Int = 0
    private var nextEnqueueIndex: Int = 0

    /// Époque de lecture incrémentée à chaque changement de piste/reprise pour invalider les anciens callbacks.
    private var playbackEpoch: UInt64 = 0

    /// Mémorise si la lecture était active avant une interruption audio système (appel entrant, Siri).
    private var wasPlayingBeforeInterruption: Bool = false

    /// Cache préchargé du prochain chapitre pour une transition sans blanc sonore.
    private var preloadedChapter: (index: Int, sentences: [LoreTTSSentence])?
    private var isPreloadingNextChapter: Bool = false

    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var currentVoice: AVSpeechSynthesisVoice?
    private var cachedArtwork: MPMediaItemArtwork?
    private var currentPlaybackTask: Task<Void, Never>?

    init(
        publication: Publication,
        bookID: UUID,
        bookTitle: String,
        bookAuthor: String?,
        coverData: Data?,
        preferences: ReaderTTSPreferences = ReaderTTSPreferences()
    ) {
        self.publication = publication
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.coverData = coverData
        self.preferences = preferences
        let coordinator = LoreTTSAudioSessionCoordinator()
        self.audioCoordinator = coordinator
        self.playbackRate = preferences.speechRate

        // Mise en cache unique de la couverture pour éviter les décodages répétitifs
        if let coverData,
           let image = UIImage(data: coverData),
           image.size.width > 0,
           image.size.height > 0 {
            self.cachedArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else {
            self.cachedArtwork = nil
        }

        super.init()

        configureCoordinator()
        setupVoice()
    }

    private func setupVoice() {
        let bookLanguage = publication.metadata.language?.code.bcp47 ?? "fr"
        let bestVoice = preferences.bestVoice(forLanguage: bookLanguage)
        self.currentVoice = bestVoice
        self.selectedVoiceName = bestVoice?.name
    }

    private func configureCoordinator() {
        audioCoordinator.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.wasPlayingBeforeInterruption = self.isPlaying
            self.pause()
        }
        audioCoordinator.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            if shouldResume && self.wasPlayingBeforeInterruption {
                self.resume()
            }
            self.wasPlayingBeforeInterruption = false
        }
        audioCoordinator.onRouteChangeOldDeviceUnavailable = { [weak self] in
            guard let self else { return }
            self.wasPlayingBeforeInterruption = false
            self.pause()
        }
    }

    // MARK: - Commandes de lecture

    func start(from locator: Locator?) {
        playbackEpoch &+= 1
        currentPlaybackTask?.cancel()
        wasPlayingBeforeInterruption = false
        currentLocator = locator
        audioCoordinator.activateSession()
        setupRemoteCommands()

        // Arrêt propre de tout synthétiseur antérieur
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer?.delegate = nil

        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        if #available(iOS 16.0, *) {
            synth.usesApplicationAudioSession = true
        }
        self.synthesizer = synth

        let targetChapterIndex: Int
        if let locator {
            targetChapterIndex = publication.readingOrder.firstIndex { $0.url().isEquivalentTo(locator.href) } ?? 0
        } else {
            targetChapterIndex = 0
        }
        self.currentChapterIndex = targetChapterIndex

        isPlaying = true
        isSpeaking = true
        updateNowPlaying()
        onStateChange?()

        currentPlaybackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.findAndPlayFirstNonEmptyChapter(from: targetChapterIndex, startLocator: locator)
        }
    }

    private func findAndPlayFirstNonEmptyChapter(from startIndex: Int, startLocator: Locator?) async {
        var index = startIndex
        while index < publication.readingOrder.count {
            guard !Task.isCancelled, isPlaying else { return }
            let extracted = await textExtractor.extractSentences(forChapterIndex: index, in: publication)
            guard !Task.isCancelled, isPlaying else { return }

            if !extracted.isEmpty {
                self.currentChapterIndex = index
                self.sentences = extracted
                let targetSentenceIndex = textExtractor.findStartingSentenceIndex(in: extracted, for: startLocator)
                self.currentSentenceIndex = targetSentenceIndex
                self.nextEnqueueIndex = targetSentenceIndex
                self.preloadedChapter = nil

                if targetSentenceIndex < extracted.count {
                    let activeLoc = extracted[targetSentenceIndex].locator
                    self.currentLocator = activeLoc
                    self.onLocationUpdate?(activeLoc)
                    self.onProgressRecord?(activeLoc)
                    self.updateNowPlaying()
                }

                self.enqueueNextSentence()
                self.enqueueNextSentence()
                return
            }
            index += 1
        }

        // Aucun texte dans les chapitres restants
        self.errorMessage = "Aucun texte lisible dans ce livre."
        self.stop()
    }

    private func enqueueNextSentence() {
        // Boucle (pas de récursion) : saute les phrases vides éventuelles
        // sans risquer d'empiler les appels. Un énoncé vide peut bloquer
        // le service vocal système ; l'extracteur borne déjà la taille.
        while let synthesizer, nextEnqueueIndex < sentences.count {
            let sentence = sentences[nextEnqueueIndex]
            nextEnqueueIndex += 1
            guard !sentence.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let utterance = SentenceUtterance(sentence: sentence, epoch: playbackEpoch)
            let baseRate = AVSpeechUtteranceDefaultSpeechRate
            let targetRate = baseRate * playbackRate
            utterance.rate = min(max(targetRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
            if let voice = currentVoice {
                utterance.voice = voice
            }

            synthesizer.speak(utterance)
            return
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        wasPlayingBeforeInterruption = false
        currentPlaybackTask?.cancel()
        synthesizer?.pauseSpeaking(at: .immediate)
        isPlaying = false
        isSpeaking = false
        updateNowPlaying()
        onStateChange?()
        if let currentLocator {
            onProgressRecord?(currentLocator)
            onPause?(currentLocator)
        }
    }

    func resume() {
        guard !sentences.isEmpty else {
            start(from: currentLocator)
            return
        }

        audioCoordinator.activateSession()
        if let synth = synthesizer, synth.isPaused {
            if synth.continueSpeaking() {
                isPlaying = true
                isSpeaking = true
                updateNowPlaying()
                onStateChange?()
                return
            }
        }

        // Si continueSpeaking échoue ou si le synthétiseur n'est pas en pause valide,
        // reprise propre à partir de la phrase active.
        restartFromCurrentSentence()
    }

    func stop() {
        playbackEpoch &+= 1
        currentPlaybackTask?.cancel()
        wasPlayingBeforeInterruption = false
        synthesizer?.stopSpeaking(at: .immediate)
        isPlaying = false
        isSpeaking = false
        updateNowPlaying()
        onStateChange?()
        if let currentLocator {
            onStop?(currentLocator)
        }
    }

    func next() {
        guard !sentences.isEmpty else { return }
        if currentSentenceIndex + 1 < sentences.count {
            currentSentenceIndex += 1
            restartFromCurrentSentence()
        } else if currentChapterIndex + 1 < publication.readingOrder.count {
            advanceToNextChapter()
        }
    }

    func previous() {
        guard !sentences.isEmpty else { return }
        if currentSentenceIndex > 0 {
            currentSentenceIndex -= 1
            restartFromCurrentSentence()
        } else if currentChapterIndex > 0 {
            goToPreviousChapter()
        }
    }

    private func restartFromCurrentSentence() {
        playbackEpoch &+= 1
        audioCoordinator.activateSession()
        synthesizer?.stopSpeaking(at: .immediate)
        nextEnqueueIndex = currentSentenceIndex
        isPlaying = true
        isSpeaking = true
        updateNowPlaying()
        onStateChange?()

        if currentSentenceIndex < sentences.count {
            let activeLoc = sentences[currentSentenceIndex].locator
            currentLocator = activeLoc
            onLocationUpdate?(activeLoc)
            onProgressRecord?(activeLoc)
        }

        enqueueNextSentence()
        enqueueNextSentence()
    }

    private func advanceToNextChapter() {
        playbackEpoch &+= 1
        synthesizer?.stopSpeaking(at: .immediate)
        currentPlaybackTask?.cancel()

        currentPlaybackTask = Task { @MainActor [weak self] in
            guard let self, self.isPlaying else { return }
            var targetIndex = self.currentChapterIndex + 1

            while targetIndex < self.publication.readingOrder.count {
                let extracted: [LoreTTSSentence]
                if let preloaded = self.preloadedChapter, preloaded.index == targetIndex {
                    extracted = preloaded.sentences
                } else {
                    extracted = await self.textExtractor.extractSentences(forChapterIndex: targetIndex, in: self.publication)
                }
                guard !Task.isCancelled, self.isPlaying else { return }

                if !extracted.isEmpty {
                    self.currentChapterIndex = targetIndex
                    self.sentences = extracted
                    self.currentSentenceIndex = 0
                    self.nextEnqueueIndex = 0
                    self.preloadedChapter = nil

                    let activeLoc = extracted[0].locator
                    self.currentLocator = activeLoc
                    self.onLocationUpdate?(activeLoc)
                    self.onProgressRecord?(activeLoc)
                    self.updateNowPlaying()

                    self.enqueueNextSentence()
                    self.enqueueNextSentence()
                    return
                }
                targetIndex += 1
            }

            // Fin du livre atteinte
            self.stop()
        }
    }

    private func goToPreviousChapter() {
        playbackEpoch &+= 1
        synthesizer?.stopSpeaking(at: .immediate)
        currentPlaybackTask?.cancel()

        currentPlaybackTask = Task { @MainActor [weak self] in
            guard let self, self.isPlaying else { return }
            var targetIndex = self.currentChapterIndex - 1

            while targetIndex >= 0 {
                let extracted = await self.textExtractor.extractSentences(forChapterIndex: targetIndex, in: self.publication)
                guard !Task.isCancelled, self.isPlaying else { return }

                if !extracted.isEmpty {
                    self.currentChapterIndex = targetIndex
                    self.sentences = extracted
                    let lastSentenceIndex = max(0, extracted.count - 1)
                    self.currentSentenceIndex = lastSentenceIndex
                    self.nextEnqueueIndex = lastSentenceIndex
                    self.preloadedChapter = nil

                    let activeLoc = extracted[lastSentenceIndex].locator
                    self.currentLocator = activeLoc
                    self.onLocationUpdate?(activeLoc)
                    self.onProgressRecord?(activeLoc)
                    self.updateNowPlaying()

                    self.restartFromCurrentSentence()
                    return
                }
                targetIndex -= 1
            }
        }
    }

    func cyclePlaybackRate() {
        playbackRate = preferences.cycleSpeechRate()
        updateNowPlaying()
    }

    var playbackRateLabel: String {
        preferences.speechRateLabel
    }

    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        currentVoice = voice
        selectedVoiceName = voice.name
        preferences.setPreferredVoiceIdentifier(voice.identifier, forLanguage: voice.language)
        if isPlaying {
            restartFromCurrentSentence()
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard let sentenceUtterance = utterance as? SentenceUtterance else { return }
        let epoch = sentenceUtterance.epoch
        let sentence = sentenceUtterance.sentence

        Task { @MainActor [weak self] in
            guard let self, epoch == self.playbackEpoch else { return }

            self.currentSentenceIndex = sentence.sentenceIndex
            self.currentLocator = sentence.locator
            self.isPlaying = true
            self.isSpeaking = true
            self.updateNowPlaying()
            self.onLocationUpdate?(sentence.locator)
            self.onProgressRecord?(sentence.locator)
            self.onStateChange?()

            // Lookahead : prépare la phrase suivante dans la file d'attente
            if self.nextEnqueueIndex < self.sentences.count {
                self.enqueueNextSentence()
            } else if !self.isPreloadingNextChapter && self.currentChapterIndex + 1 < self.publication.readingOrder.count {
                self.preloadNextChapter()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard let sentenceUtterance = utterance as? SentenceUtterance else { return }
        let epoch = sentenceUtterance.epoch
        let sentenceIndex = sentenceUtterance.sentence.sentenceIndex

        Task { @MainActor [weak self] in
            guard let self, epoch == self.playbackEpoch else { return }

            // Vérifie si l'énoncé qui vient de se terminer est bien le dernier du chapitre
            let isLastSentence = sentenceIndex >= self.sentences.count - 1
            if isLastSentence {
                if self.currentChapterIndex + 1 < self.publication.readingOrder.count {
                    self.advanceToNextChapter()
                } else {
                    self.stop()
                }
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Annulation propre ignorée grâce au filtrage par playbackEpoch
    }

    private func preloadNextChapter() {
        guard !isPreloadingNextChapter else { return }
        let nextIndex = currentChapterIndex + 1
        guard nextIndex < publication.readingOrder.count else { return }
        isPreloadingNextChapter = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            let extracted = await self.textExtractor.extractSentences(forChapterIndex: nextIndex, in: self.publication)
            if self.currentChapterIndex + 1 == nextIndex {
                self.preloadedChapter = (nextIndex, extracted)
            }
            self.isPreloadingNextChapter = false
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
        if let cachedArtwork {
            info[MPMediaItemPropertyArtwork] = cachedArtwork
        }
        if let totalProgression = currentLocator?.locations.totalProgression,
           !totalProgression.isNaN,
           !totalProgression.isInfinite,
           totalProgression >= 0 {
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
        playbackEpoch &+= 1
        currentPlaybackTask?.cancel()
        wasPlayingBeforeInterruption = false
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer?.delegate = nil
        synthesizer = nil
        isPlaying = false
        isSpeaking = false
        Self.clearSystemAudio()
        audioCoordinator.deactivateSession()

        for (command, token) in remoteTargets {
            command.removeTarget(token)
            command.isEnabled = false
        }
        remoteTargets = []
    }

    /// Nettoyage système appelable depuis `deinit` (contexte non isolé).
    /// Ne touche à aucun état `@MainActor` : efface uniquement le
    /// `Now Playing` et désactive la session audio partagée.
    /// Le nettoyage complet reste dans `teardown()` via `close()`.
    nonisolated static func clearSystemAudio() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit {
        Self.clearSystemAudio()
    }
}

// MARK: - SentenceUtterance

private final class SentenceUtterance: AVSpeechUtterance, @unchecked Sendable {
    let sentence: LoreTTSSentence
    let epoch: UInt64

    init(sentence: LoreTTSSentence, epoch: UInt64) {
        self.sentence = sentence
        self.epoch = epoch
        super.init(string: sentence.text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
