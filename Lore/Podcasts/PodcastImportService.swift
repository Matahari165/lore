import AVFoundation
import Foundation

@MainActor
protocol PodcastImportValidating {
    func validateMP4(at fileURL: URL) async throws -> Double?
}

struct AVPodcastImportValidator: PodcastImportValidating {
    func validateMP4(at fileURL: URL) async throws -> Double? {
        let asset = AVURLAsset(url: fileURL)
        guard try await asset.load(.isPlayable) else {
            throw PodcastImportServiceError.notPlayable
        }
        let duration = try await asset.load(.duration).seconds
        return duration.isFinite && duration > 0 ? duration : nil
    }
}

enum PodcastImportResult: Equatable {
    case imported
    case alreadyImported
}

@MainActor
private final class PodcastImportGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
final class PodcastImportService {
    private let repository: PodcastRepository
    private let fileStore: PodcastFileStore
    private let validator: any PodcastImportValidating
    private let gate = PodcastImportGate()

    init(
        repository: PodcastRepository,
        fileStore: PodcastFileStore,
        validator: any PodcastImportValidating = AVPodcastImportValidator()
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.validator = validator
    }

    func importMP4(from sourceURL: URL) async throws -> PodcastImportResult {
        await gate.acquire()
        defer { gate.release() }

        let fileStore = self.fileStore
        let staged = try await Task.detached {
            try fileStore.stageMP4(from: sourceURL)
        }.value
        if try repository.podcast(contentSHA256: staged.contentSHA256) != nil {
            fileStore.discard(staged)
            return .alreadyImported
        }

        var reservedPodcast: PodcastRecord?
        do {
            let durationSeconds = try await validator.validateMP4(at: staged.fileURL)
            let record = PodcastRecord(
                contentSHA256: staged.contentSHA256,
                title: Self.title(from: sourceURL),
                originalFilename: sourceURL.lastPathComponent,
                relativeFilePath: "",
                durationSeconds: durationSeconds,
                importState: .pending,
                stagingToken: staged.token
            )
            try repository.add(record)
            reservedPodcast = record
            let podcastID = record.id
            let relativePath = try await Task.detached {
                try fileStore.promote(staged, to: podcastID)
            }.value
            try repository.confirmImport(podcastID: record.id, relativeFilePath: relativePath)
            return .imported
        } catch {
            if reservedPodcast == nil {
                fileStore.discard(staged)
            }
            throw error
        }
    }

    func reconcileImports(now: Date = .now) throws -> PodcastFileReconciliationReport {
        var report = PodcastFileReconciliationReport()
        for podcast in try repository.pendingImports() {
            do {
                try recoverImport(podcast)
            } catch {
                try repository.markRecoveryRequired(podcastID: podcast.id)
            }
        }

        let podcasts = try repository.podcasts()
        let fileReport = try fileStore.reconcile(
            referencedPodcastIDs: Set(podcasts.map(\.id)),
            referencedStagingTokens: Set(podcasts.compactMap(\.stagingToken)),
            now: now
        )
        report = fileReport
        return report
    }

    private func recoverImport(_ podcast: PodcastRecord) throws {
        guard let digest = podcast.contentSHA256 else {
            throw PodcastFileStoreError.storedFileMissing
        }
        if (try? fileStore.finalFile(podcastID: podcast.id, expectedSHA256: digest)) != nil {
            try repository.confirmImport(
                podcastID: podcast.id,
                relativeFilePath: "Podcasts/\(podcast.id.uuidString)/episode.mp4"
            )
        } else if let token = podcast.stagingToken {
            let staged = try fileStore.stagedFile(token: token, expectedSHA256: digest)
            let path = try fileStore.promote(staged, to: podcast.id)
            try repository.confirmImport(podcastID: podcast.id, relativeFilePath: path)
        } else {
            throw PodcastFileStoreError.storedFileMissing
        }
    }

    private static func title(from url: URL) -> String {
        let rawTitle = url.deletingPathExtension().lastPathComponent
        let title = rawTitle
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Podcast sans titre" : title
    }

}

enum PodcastImportServiceError: LocalizedError, Equatable {
    case notPlayable

    var errorDescription: String? {
        switch self {
        case .notPlayable:
            "Ce MP4 ne peut pas être lu par Lore."
        }
    }
}
