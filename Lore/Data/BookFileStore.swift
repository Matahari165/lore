import CryptoKit
import Foundation

enum BookFileStoreError: LocalizedError, Equatable {
    case sourceUnavailable, unsupportedFileType, destinationAlreadyExists
    case copyFailed, storedFileMissing, invalidStagingToken

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: "Le fichier sélectionné n’est plus accessible."
        case .unsupportedFileType: "Le fichier sélectionné n’est pas un EPUB."
        case .destinationAlreadyExists: "Un fichier existe déjà pour ce livre."
        case .copyFailed: "L’EPUB n’a pas pu être copié dans Lore."
        case .storedFileMissing: "Le fichier EPUB enregistré est introuvable."
        case .invalidStagingToken: "La copie temporaire de l’EPUB est invalide."
        }
    }
}

struct StagedBookFile: Sendable, Equatable {
    let token: UUID
    let fileURL: URL
    let contentSHA256: String
}

struct BookFileReconciliationReport: Sendable, Equatable {
    var removedStagingTokens: [UUID] = []
    var orphanBookIDs: [UUID] = []
    var quarantinedBookIDs: [UUID] = []
    var missingBookIDs: [UUID] = []
    var quarantineReviewAfter: Date?
}

struct BookFileStore: Sendable {
    private let applicationSupportURL: URL

    init(applicationSupportURL: URL? = nil) throws {
        if let applicationSupportURL {
            self.applicationSupportURL = applicationSupportURL
        } else {
            guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw BookFileStoreError.sourceUnavailable
            }
            self.applicationSupportURL = url
        }
    }

    /// Copies the security-scoped source once into Lore's private staging area.
    /// Readium must validate this exact `fileURL` before promotion.
    func stageEPUB(from sourceURL: URL) throws -> StagedBookFile {
        guard sourceURL.pathExtension.lowercased() == "epub" else {
            throw BookFileStoreError.unsupportedFileType
        }
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw BookFileStoreError.sourceUnavailable
        }

        let token = UUID()
        let directory = stagingDirectory(for: token)
        let fileURL = directory.appendingPathComponent("book.epub")
        do {
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
            try fileManager.copyItem(at: sourceURL, to: fileURL)
            return StagedBookFile(token: token, fileURL: fileURL, contentSHA256: try sha256(of: fileURL))
        } catch {
            try? fileManager.removeItem(at: directory)
            throw (error as? BookFileStoreError) ?? BookFileStoreError.copyFailed
        }
    }

    func stagedFile(token: UUID, expectedSHA256: String) throws -> StagedBookFile {
        let url = stagingDirectory(for: token).appendingPathComponent("book.epub")
        guard fileManager.fileExists(atPath: url.path) else { throw BookFileStoreError.invalidStagingToken }
        let digest = try sha256(of: url)
        guard digest == expectedSHA256 else { throw BookFileStoreError.invalidStagingToken }
        return StagedBookFile(token: token, fileURL: url, contentSHA256: digest)
    }

    func promote(_ staged: StagedBookFile, to bookID: UUID) throws -> String {
        let expectedDirectory = stagingDirectory(for: staged.token).standardizedFileURL
        guard staged.fileURL.deletingLastPathComponent().standardizedFileURL == expectedDirectory,
              try sha256(of: staged.fileURL) == staged.contentSHA256 else {
            throw BookFileStoreError.invalidStagingToken
        }
        let destinationDirectory = booksRoot.appendingPathComponent(bookID.uuidString, isDirectory: true)
        let destinationURL = destinationDirectory.appendingPathComponent("book.epub")
        guard !fileManager.fileExists(atPath: destinationDirectory.path) else {
            throw BookFileStoreError.destinationAlreadyExists
        }
        do {
            try fileManager.moveItem(at: expectedDirectory, to: destinationDirectory)
            return relativePath(for: destinationURL)
        } catch {
            throw BookFileStoreError.copyFailed
        }
    }

    func discard(_ staged: StagedBookFile) {
        try? fileManager.removeItem(at: stagingDirectory(for: staged.token))
    }

    func fileURL(for relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3, components[0] == "Books",
              UUID(uuidString: String(components[1])) != nil, components[2] == "book.epub" else {
            throw BookFileStoreError.storedFileMissing
        }
        let root = applicationSupportURL.standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"), fileManager.fileExists(atPath: candidate.path) else {
            throw BookFileStoreError.storedFileMissing
        }
        return candidate
    }

    func finalFile(bookID: UUID, expectedSHA256: String) throws -> URL {
        let url = booksRoot.appendingPathComponent(bookID.uuidString).appendingPathComponent("book.epub")
        guard fileManager.fileExists(atPath: url.path), try sha256(of: url) == expectedSHA256 else {
            throw BookFileStoreError.storedFileMissing
        }
        return url
    }

    func relativePath(forBookID bookID: UUID) -> String { "Books/\(bookID.uuidString)/book.epub" }

    @discardableResult
    func quarantineFinalDirectory(bookID: UUID, now: Date = .now) throws -> URL? {
        let source = booksRoot.appendingPathComponent(bookID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        try fileManager.createDirectory(at: quarantineRoot, withIntermediateDirectories: true)
        let timestamp = Int(now.timeIntervalSince1970)
        var destination = quarantineRoot.appendingPathComponent("\(bookID.uuidString)-\(timestamp)", isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            destination = quarantineRoot.appendingPathComponent("\(bookID.uuidString)-\(timestamp)-\(UUID().uuidString)")
        }
        try fileManager.moveItem(at: source, to: destination)
        return destination
    }

    func removeBookFile(at relativePath: String) throws {
        try fileManager.removeItem(at: try fileURL(for: relativePath).deletingLastPathComponent())
    }

    func reconcile(
        referencedBookIDs: Set<UUID>,
        referencedStagingTokens: Set<UUID>,
        now: Date = .now,
        staleAfter: TimeInterval = 24 * 60 * 60,
        quarantineOrphansAfter: TimeInterval = 7 * 24 * 60 * 60
    ) throws -> BookFileReconciliationReport {
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        var report = BookFileReconciliationReport()
        for url in try directoryContents(at: stagingRoot) {
            guard let token = UUID(uuidString: url.lastPathComponent), !referencedStagingTokens.contains(token) else { continue }
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard let modified, now.timeIntervalSince(modified) >= staleAfter else { continue }
            try fileManager.removeItem(at: url)
            report.removedStagingTokens.append(token)
        }
        for url in try directoryContents(at: booksRoot)
        where url.lastPathComponent != ".staging" && url.lastPathComponent != ".quarantine" {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            if !referencedBookIDs.contains(id) {
                let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if let modified, now.timeIntervalSince(modified) >= quarantineOrphansAfter {
                    _ = try quarantineFinalDirectory(bookID: id, now: now)
                    report.quarantinedBookIDs.append(id)
                } else {
                    report.orphanBookIDs.append(id)
                }
            }
        }
        for id in referencedBookIDs {
            let url = booksRoot.appendingPathComponent(id.uuidString).appendingPathComponent("book.epub")
            if !fileManager.fileExists(atPath: url.path) { report.missingBookIDs.append(id) }
        }
        if !report.quarantinedBookIDs.isEmpty {
            report.quarantineReviewAfter = now.addingTimeInterval(7 * 24 * 60 * 60)
        }
        return report
    }

    func sha256(of fileURL: URL) throws -> String {
        guard let stream = InputStream(url: fileURL) else { throw BookFileStoreError.sourceUnavailable }
        stream.open()
        defer { stream.close() }
        var hash = SHA256()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64 * 1024)
        defer { buffer.deallocate() }
        while true {
            let count = stream.read(buffer, maxLength: 64 * 1024)
            if count < 0 { throw stream.streamError ?? BookFileStoreError.copyFailed }
            if count == 0 { break }
            hash.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private var booksRoot: URL { applicationSupportURL.appendingPathComponent("Books", isDirectory: true) }
    private var fileManager: FileManager { .default }
    private var stagingRoot: URL { booksRoot.appendingPathComponent(".staging", isDirectory: true) }
    private var quarantineRoot: URL { booksRoot.appendingPathComponent(".quarantine", isDirectory: true) }
    private func stagingDirectory(for token: UUID) -> URL {
        stagingRoot.appendingPathComponent(token.uuidString, isDirectory: true)
    }
    private func directoryContents(at url: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey])
    }
    private func relativePath(for url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(applicationSupportURL.standardizedFileURL.path.count + 1))
    }
}
