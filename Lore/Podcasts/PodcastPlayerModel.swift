import AVFoundation
import Foundation
import MediaPlayer
import Observation

@MainActor
@Observable
final class PodcastPlayerModel {
    let podcast: PodcastRecord
    let repository: PodcastRepository
    let player = AVPlayer()

    private(set) var duration: Double
    private(set) var currentTime: Double
    private(set) var isPlaying = false
    private(set) var isReady = false
    var errorMessage: String?
    private var lastPersistedPosition: Double
    private nonisolated(unsafe) var interruptionObserver: NSObjectProtocol?
    private var remoteTargets: [(MPRemoteCommand, Any)] = []

    init(podcast: PodcastRecord, repository: PodcastRepository) {
        self.podcast = podcast
        self.repository = repository
        duration = podcast.durationSeconds ?? 0
        currentTime = podcast.lastPositionSeconds
        lastPersistedPosition = podcast.lastPositionSeconds
        observeInterruptions()
    }

    func load(fileURL: URL) async {
        guard !isReady else { return }
        configureAudioSession()
        do {
            let asset = AVURLAsset(url: fileURL)
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else { throw PodcastPlayerModelError.notPlayable }
            let loadedDuration = try await asset.load(.duration).seconds
            if loadedDuration.isFinite, loadedDuration > 0 {
                duration = loadedDuration
            }
            // Diagnostic : présence d'une piste audio (non bloquant si absente).
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if audioTracks.isEmpty {
                errorMessage = "Ce MP4 ne contient pas de piste audio : la vidéo sera muette."
            }
            player.isMuted = false
            player.volume = 1.0
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            let start = min(max(podcast.lastPositionSeconds, 0), max(duration, 0))
            currentTime = start
            await player.seek(
                to: CMTime(seconds: start, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            isReady = true
            setupRemoteCommands()
            updateNowPlaying()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refresh() {
        guard isReady else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        currentTime = min(max(seconds, 0), max(duration, 0))
        if duration > 0, currentTime >= duration - 0.5 {
            let shouldPersist = isPlaying || abs(currentTime - lastPersistedPosition) >= 0.5
            isPlaying = false
            player.pause()
            updateNowPlaying()
            if shouldPersist { persist() }
        } else if isPlaying, abs(currentTime - lastPersistedPosition) >= 2 {
            persist()
        }
    }

    func togglePlayback() {
        guard isReady else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            persist()
        } else {
            if duration > 0, currentTime >= duration - 0.5 {
                seek(to: 0)
            }
            activateSessionForPlayback()
            player.isMuted = false
            player.volume = 1.0
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        guard isReady else { return }
        let target = min(max(seconds, 0), max(duration, 0))
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        updateNowPlaying()
    }

    func pauseAndSave() {
        guard isReady else { return }
        player.pause()
        isPlaying = false
        refresh()
        persist()
    }

    func persist() {
        do {
            try repository.savePosition(for: podcast.id, seconds: currentTime)
            lastPersistedPosition = currentTime
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Verrouillage ou arrière-plan : enregistre la position sans couper le son.
    func savePositionOnly() {
        guard isReady else { return }
        refresh()
        persist()
    }

    /// Fermeture du lecteur : arrête la lecture et nettoie l'écran verrouillé.
    func teardown() {
        pauseAndSave()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        for (command, token) in remoteTargets {
            command.removeTarget(token)
        }
        remoteTargets = []
    }

        // MARK: - Écran verrouillé

    /// Titre, durée et position affichés sur l'écran verrouillé et dans le centre de contrôle.
    /// Le système fait avancer le temps tout seul grâce au débit indiqué (1 en lecture, 0 en pause).
    private func updateNowPlaying() {
        guard isReady else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: podcast.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    /// Boutons Lecture/Pause/±15 s et curseur utilisables depuis l'écran verrouillé.
    private func setupRemoteCommands() {
        guard remoteTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.changePlaybackPositionCommand.isEnabled = true

        remoteTargets = [
            (center.playCommand, center.playCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady, !self.isPlaying else { return }
                    self.togglePlayback()
                }
                return .success
            }),
            (center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady, self.isPlaying else { return }
                    self.togglePlayback()
                }
                return .success
            }),
            (center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady else { return }
                    self.togglePlayback()
                }
                return .success
            }),
            (center.skipBackwardCommand, center.skipBackwardCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady else { return }
                    self.seek(to: self.currentTime - 15)
                    self.persist()
                }
                return .success
            }),
            (center.skipForwardCommand, center.skipForwardCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady else { return }
                    self.seek(to: self.currentTime + 15)
                    self.persist()
                }
                return .success
            }),
            (center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.addTarget { [weak self] event in
                Task { @MainActor in
                    guard let self, self.isReady,
                          let event = event as? MPChangePlaybackPositionCommandEvent else { return }
                    self.seek(to: event.positionTime)
                    self.persist()
                }
                return .success
            }),
        ]
    }

    // MARK: - Audio

    /// Catégorie `.playback` : le son reste audible même si l'iPhone est en mode
    /// silencieux. Erreur non bloquante : la lecture est tentée quand même.
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            errorMessage = "Audio indisponible : \(error.localizedDescription)"
        }
    }

    private func activateSessionForPlayback() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = "Audio indisponible : \(error.localizedDescription)"
        }
    }

    /// Appel téléphonique, Siri, alarme… : pause immédiate + sauvegarde de la position.
    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let info = notification.userInfo
            let rawType = info?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self, rawType, optionsRaw] in
                self?.handleInterruption(rawType: rawType, optionsRaw: optionsRaw)
            }
        }
    }

    private func handleInterruption(rawType: UInt?, optionsRaw: UInt) {
        guard let rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }
        switch type {
        case .began:
            pauseAndSave()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume), isReady, !isPlaying {
                togglePlayback()
            }
        @unknown default:
            pauseAndSave()
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }
}

enum PodcastPlayerModelError: LocalizedError, Equatable {
    case notPlayable

    var errorDescription: String? {
        switch self {
        case .notPlayable:
            "Ce MP4 ne peut pas être lu par Lore."
        }
    }
}
