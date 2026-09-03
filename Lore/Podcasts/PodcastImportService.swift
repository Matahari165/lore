import AVFoundation
import Foundation

enum PodcastImportResult: Equatable {
    case imported
    case alreadyImported
}

@MainActor
final class PodcastImportService {
    private let repository: PodcastRepository
    private let fileStore: PodcastFileStore

    init(repository: PodcastRepository, fileStore: PodcastFileStore) {
        self.repository = repository
        self.fileStore = fileStore
    }

    func importMP4(from sourceURL: URL) async throws -> PodcastImportResult {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw PodcastFileStoreError.sourceUnavailable
        }
        guard sourceURL.pathExtension.lowercased() == "mp4" else {
            throw PodcastFileStoreError.unsupportedFileType
        }

        let fileStore = self.fileStore
        let digest = try await Task.detached {
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
            return try fileStore.contentSHA256(of: sourceURL)
        }.value
        if try repository.podcast(contentSHA256: digest) != nil {
            return .alreadyImported
        }

        let podcastID = UUID()
        let relativePath = try await Task.detached {
            try fileStore.copyMP4(from: sourceURL, podcastID: podcastID)
        }.value
        do {
            let storedURL = try fileStore.fileURL(for: relativePath)
            let asset = AVURLAsset(url: storedURL)
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else { throw PodcastImportServiceError.notPlayable }
            let duration = try await asset.load(.duration)
            let durationSeconds = duration.seconds.isFinite && duration.seconds > 0
                ? duration.seconds
                : nil
            let record = PodcastRecord(
                contentSHA256: digest,
                title: Self.title(from: sourceURL),
                originalFilename: sourceURL.lastPathComponent,
                relativeFilePath: relativePath,
                durationSeconds: durationSeconds
            )
            try repository.add(record)
            return .imported
        } catch {
            try? fileStore.removeFile(at: relativePath)
            throw error
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

    private var fileManager: FileManager { .default }
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
