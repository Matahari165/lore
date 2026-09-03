import AVFoundation
import Foundation
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

    init(podcast: PodcastRecord, repository: PodcastRepository) {
        self.podcast = podcast
        self.repository = repository
        duration = podcast.durationSeconds ?? 0
        currentTime = podcast.lastPositionSeconds
        lastPersistedPosition = podcast.lastPositionSeconds
    }

    func load(fileURL: URL) async {
        guard !isReady else { return }
        do {
            let asset = AVURLAsset(url: fileURL)
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else { throw PodcastPlayerModelError.notPlayable }
            let loadedDuration = try await asset.load(.duration).seconds
            if loadedDuration.isFinite, loadedDuration > 0 {
                duration = loadedDuration
            }
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            let start = min(max(podcast.lastPositionSeconds, 0), max(duration, 0))
            currentTime = start
            await player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
            isReady = true
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
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        guard isReady else { return }
        let target = min(max(seconds, 0), max(duration, 0))
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
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
