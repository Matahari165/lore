import CryptoKit
import Foundation

enum PodcastFileStoreError: LocalizedError, Equatable {
    case sourceUnavailable
    case unsupportedFileType
    case destinationAlreadyExists
    case copyFailed
    case storedFileMissing
    case invalidStagingToken

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "Le fichier sélectionné n’est plus accessible."
        case .unsupportedFileType:
            "Le fichier sélectionné n’est pas un MP4."
        case .destinationAlreadyExists:
            "Un fichier existe déjà pour ce podcast."
        case .copyFailed:
            "Le podcast n’a pas pu être copié dans Lore."
        case .storedFileMissing:
            "Le fichier du podcast est introuvable."
        case .invalidStagingToken:
            "La copie temporaire du podcast est invalide."
        }
    }
}

struct StagedPodcastFile: Sendable, Equatable {
    let token: UUID
    let fileURL: URL
    let contentSHA256: String
}

struct PodcastFileReconciliationReport: Sendable, Equatable {
    var removedStagingTokens: [UUID] = []
    var orphanPodcastIDs: [UUID] = []
    var quarantinedPodcastIDs: [UUID] = []
    var missingPodcastIDs: [UUID] = []
    var quarantineReviewAfter: Date?
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

    /// Copies an external URL once into private staging and hashes that exact copy.
    func stageMP4(from sourceURL: URL) throws -> StagedPodcastFile {
        guard sourceURL.pathExtension.lowercased() == "mp4" else {
            throw PodcastFileStoreError.unsupportedFileType
        }

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        guard didAccess || fileManager.isReadableFile(atPath: sourceURL.path),
              fileManager.fileExists(atPath: sourceURL.path) else {
            throw PodcastFileStoreError.sourceUnavailable
        }

        let token = UUID()
        let directory = stagingDirectory(for: token)
        let destination = directory.appendingPathComponent("episode.mp4")
        do {
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
            try fileManager.copyItem(at: sourceURL, to: destination)
            return StagedPodcastFile(token: token, fileURL: destination, contentSHA256: try contentSHA256(of: destination))
        } catch {
            try? fileManager.removeItem(at: directory)
            throw (error as? PodcastFileStoreError) ?? PodcastFileStoreError.copyFailed
        }
    }

    func stagedFile(token: UUID, expectedSHA256: String) throws -> StagedPodcastFile {
        let url = stagingDirectory(for: token).appendingPathComponent("episode.mp4")
        guard fileManager.fileExists(atPath: url.path) else {
            throw PodcastFileStoreError.invalidStagingToken
        }
        let digest = try contentSHA256(of: url)
        guard digest == expectedSHA256 else {
            throw PodcastFileStoreError.invalidStagingToken
        }
        return StagedPodcastFile(token: token, fileURL: url, contentSHA256: digest)
    }

    func promote(_ staged: StagedPodcastFile, to podcastID: UUID) throws -> String {
        let expectedDirectory = stagingDirectory(for: staged.token).standardizedFileURL
        guard staged.fileURL.deletingLastPathComponent().standardizedFileURL == expectedDirectory,
              try contentSHA256(of: staged.fileURL) == staged.contentSHA256 else {
            throw PodcastFileStoreError.invalidStagingToken
        }

        let destinationDirectory = podcastsRoot.appendingPathComponent(podcastID.uuidString, isDirectory: true)
        guard !fileManager.fileExists(atPath: destinationDirectory.path) else {
            throw PodcastFileStoreError.destinationAlreadyExists
        }
        do {
            try fileManager.moveItem(at: expectedDirectory, to: destinationDirectory)
            return relativePath(for: podcastID)
        } catch {
            throw PodcastFileStoreError.copyFailed
        }
    }

    func discard(_ staged: StagedPodcastFile) {
        try? fileManager.removeItem(at: stagingDirectory(for: staged.token))
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

    func finalFile(podcastID: UUID, expectedSHA256: String) throws -> URL {
        let url = podcastsRoot.appendingPathComponent(podcastID.uuidString).appendingPathComponent("episode.mp4")
        guard fileManager.fileExists(atPath: url.path), try contentSHA256(of: url) == expectedSHA256 else {
            throw PodcastFileStoreError.storedFileMissing
        }
        return url
    }

    @discardableResult
    func quarantineFinalDirectory(podcastID: UUID, now: Date = .now) throws -> URL? {
        let source = podcastsRoot.appendingPathComponent(podcastID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        try fileManager.createDirectory(at: quarantineRoot, withIntermediateDirectories: true)
        let timestamp = Int(now.timeIntervalSince1970)
        var destination = quarantineRoot.appendingPathComponent("\(podcastID.uuidString)-\(timestamp)", isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            destination = quarantineRoot.appendingPathComponent("\(podcastID.uuidString)-\(timestamp)-\(UUID().uuidString)", isDirectory: true)
        }
        try fileManager.moveItem(at: source, to: destination)
        return destination
    }

    func reconcile(
        referencedPodcastIDs: Set<UUID>,
        referencedStagingTokens: Set<UUID>,
        now: Date = .now,
        staleAfter: TimeInterval = 24 * 60 * 60,
        quarantineOrphansAfter: TimeInterval = 7 * 24 * 60 * 60
    ) throws -> PodcastFileReconciliationReport {
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        var report = PodcastFileReconciliationReport()
        for url in try directoryContents(at: stagingRoot) {
            guard let token = UUID(uuidString: url.lastPathComponent), !referencedStagingTokens.contains(token) else { continue }
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard let modified, now.timeIntervalSince(modified) >= staleAfter else { continue }
            try fileManager.removeItem(at: url)
            report.removedStagingTokens.append(token)
        }
        for url in try directoryContents(at: podcastsRoot)
        where url.lastPathComponent != ".staging" && url.lastPathComponent != ".quarantine" {
            guard let id = UUID(uuidString: url.lastPathComponent), !referencedPodcastIDs.contains(id) else { continue }
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, now.timeIntervalSince(modified) >= quarantineOrphansAfter {
                _ = try quarantineFinalDirectory(podcastID: id, now: now)
                report.quarantinedPodcastIDs.append(id)
            } else {
                report.orphanPodcastIDs.append(id)
            }
        }
        for id in referencedPodcastIDs {
            let url = podcastsRoot.appendingPathComponent(id.uuidString).appendingPathComponent("episode.mp4")
            if !fileManager.fileExists(atPath: url.path) { report.missingPodcastIDs.append(id) }
        }
        if !report.quarantinedPodcastIDs.isEmpty {
            report.quarantineReviewAfter = now.addingTimeInterval(7 * 24 * 60 * 60)
        }
        return report
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

    private var stagingRoot: URL {
        podcastsRoot.appendingPathComponent(".staging", isDirectory: true)
    }

    private var quarantineRoot: URL {
        podcastsRoot.appendingPathComponent(".quarantine", isDirectory: true)
    }

    private var fileManager: FileManager { .default }

    private func relativePath(for podcastID: UUID) -> String {
        "Podcasts/\(podcastID.uuidString)/episode.mp4"
    }

    private func stagingDirectory(for token: UUID) -> URL {
        stagingRoot.appendingPathComponent(token.uuidString, isDirectory: true)
    }

    private func directoryContents(at url: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey])
    }
}
