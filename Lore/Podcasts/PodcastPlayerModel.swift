import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

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
    private(set) var playbackRate: Float = 1.0
    private var lockScreenArtist: String?
    private var lockScreenArtwork: MPMediaItemArtwork?

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
            lockScreenArtist = await Self.artistName(from: asset)
            lockScreenArtwork = await Self.artwork(from: asset, duration: duration)
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
            player.rate = playbackRate
            isPlaying = true
        }
        updateNowPlaying()
    }

    /// Vitesses proposées, dans l'ordre : 1 → 1,25 → 1,5 → 1,75 → 2 → 1…
    private static let availableRates: [Float] = [1, 1.25, 1.5, 1.75, 2]

    func cyclePlaybackRate() {
        guard isReady else { return }
        let current = Self.availableRates.firstIndex(of: playbackRate) ?? 0
        playbackRate = Self.availableRates[(current + 1) % Self.availableRates.count]
        if isPlaying {
            player.rate = playbackRate
        }
        updateNowPlaying()
    }

    var playbackRateLabel: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        return (formatter.string(from: NSNumber(value: playbackRate)) ?? "\(playbackRate)") + "×"
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

    /// Nom d'artiste intégré au fichier MP4, s'il existe.
    private static func artistName(from asset: AVURLAsset) async -> String? {
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        for item in items where item.commonKey == .commonKeyArtist {
            if let name = item.stringValue, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    /// Pochette de l'écran verrouillé : image intégrée au fichier si présente,
    /// sinon une image extraite de la vidéo.
    /// Non isolée : le système appelle la fourniture d'image en arrière-plan,
    /// ce qui planterait si elle héritait du fil principal.
    private nonisolated static func artwork(from asset: AVURLAsset, duration: Double) async -> MPMediaItemArtwork? {
        if let items = try? await asset.load(.commonMetadata) {
            for item in items where item.commonKey == .commonKeyArtwork {
                if let data = item.dataValue, let image = UIImage(data: data) {
                    return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
            }
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        let safeDuration = max(duration, 1)
        let position = min(max(safeDuration * 0.05, 1.0), 60.0)
        if let result = try? await generator.image(at: CMTime(seconds: position, preferredTimescale: 600)) {
            let image = UIImage(cgImage: result.image)
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        return nil
    }

    /// Titre, durée et position affichés sur l'écran verrouillé et dans le centre de contrôle.
    /// Le système fait avancer le temps tout seul grâce au débit indiqué (1 en lecture, 0 en pause).
    private func updateNowPlaying() {
        guard isReady else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: podcast.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0,
        ]
        if let lockScreenArtist {
            info[MPMediaItemPropertyArtist] = lockScreenArtist
        }
        if let lockScreenArtwork {
            info[MPMediaItemPropertyArtwork] = lockScreenArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
            (center.playCommand, center.playCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady, !self.isPlaying else { return }
                    self.togglePlayback()
                }
                return .success
            }),
            (center.pauseCommand, center.pauseCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady, self.isPlaying else { return }
                    self.togglePlayback()
                }
                return .success
            }),
            (center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady else { return }
                    self.togglePlayback()
                }
                return .success
            }),
            (center.skipBackwardCommand, center.skipBackwardCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady else { return }
                    self.seek(to: self.currentTime - 15)
                    self.persist()
                }
                return .success
            }),
            (center.skipForwardCommand, center.skipForwardCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady else { return }
                    self.seek(to: self.currentTime + 15)
                    self.persist()
                }
                return .success
            }),
            (center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
                let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
                Task { @MainActor in
                    guard let self, self.isReady, let position else { return }
                    self.seek(to: position)
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
