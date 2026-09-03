import CryptoKit
import Foundation

enum PodcastFileStoreError: LocalizedError, Equatable {
    case sourceUnavailable
    case unsupportedFileType
    case copyFailed
    case storedFileMissing

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "Le fichier sélectionné n’est plus accessible."
        case .unsupportedFileType:
            "Le fichier sélectionné n’est pas un MP4."
        case .copyFailed:
            "Le podcast n’a pas pu être copié dans Lore."
        case .storedFileMissing:
            "Le fichier du podcast est introuvable."
        }
    }
}

struct PodcastFileStore: Sendable {
    private let applicationSupportURL: URL

    init(applicationSupportURL: URL? = nil) throws {
        if let applicationSupportURL {
            self.applicationSupportURL = applicationSupportURL
        } else {
            guard let url = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw PodcastFileStoreError.sourceUnavailable
            }
            self.applicationSupportURL = url
        }
    }

    func copyMP4(from sourceURL: URL, podcastID: UUID) throws -> String {
        guard sourceURL.pathExtension.lowercased() == "mp4" else {
            throw PodcastFileStoreError.unsupportedFileType
        }

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw PodcastFileStoreError.sourceUnavailable
        }

        let directory = podcastsRoot.appendingPathComponent(podcastID.uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent("episode.mp4")
        let directoryAlreadyExists = fileManager.fileExists(atPath: directory.path)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: destination)
            return relativePath(for: podcastID)
        } catch {
            if !directoryAlreadyExists { try? fileManager.removeItem(at: directory) }
            throw PodcastFileStoreError.copyFailed
        }
    }

    func fileURL(for relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "Podcasts",
              UUID(uuidString: String(components[1])) != nil,
              components[2] == "episode.mp4"
        else {
            throw PodcastFileStoreError.storedFileMissing
        }

        let root = applicationSupportURL.standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"),
              fileManager.fileExists(atPath: candidate.path)
        else {
            throw PodcastFileStoreError.storedFileMissing
        }
        return candidate
    }

    func removeFile(at relativePath: String) throws {
        try fileManager.removeItem(at: try fileURL(for: relativePath).deletingLastPathComponent())
    }

    func contentSHA256(of fileURL: URL) throws -> String {
        guard let stream = InputStream(url: fileURL) else {
            throw PodcastFileStoreError.sourceUnavailable
        }
        stream.open()
        defer { stream.close() }

        var hash = SHA256()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64 * 1024)
        defer { buffer.deallocate() }
        while true {
            let count = stream.read(buffer, maxLength: 64 * 1024)
            if count < 0 { throw stream.streamError ?? PodcastFileStoreError.sourceUnavailable }
            if count == 0 { break }
            hash.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private var podcastsRoot: URL {
        applicationSupportURL.appendingPathComponent("Podcasts", isDirectory: true)
    }

    private var fileManager: FileManager { .default }

    private func relativePath(for podcastID: UUID) -> String {
        "Podcasts/\(podcastID.uuidString)/episode.mp4"
    }
}
