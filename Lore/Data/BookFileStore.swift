import Foundation

enum BookFileStoreError: LocalizedError, Equatable {
    case sourceUnavailable
    case unsupportedFileType
    case destinationAlreadyExists
    case copyFailed
    case storedFileMissing

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "Le fichier sélectionné n’est plus accessible."
        case .unsupportedFileType:
            "Le fichier sélectionné n’est pas un EPUB."
        case .destinationAlreadyExists:
            "Un fichier existe déjà pour ce livre."
        case .copyFailed:
            "L’EPUB n’a pas pu être copié dans Lore."
        case .storedFileMissing:
            "Le fichier EPUB enregistré est introuvable."
        }
    }
}

struct BookFileStore: Sendable {
    private let applicationSupportURL: URL

    init(applicationSupportURL: URL? = nil) throws {
        if let applicationSupportURL {
            self.applicationSupportURL = applicationSupportURL
        } else {
            guard let url = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw BookFileStoreError.sourceUnavailable
            }
            self.applicationSupportURL = url
        }
    }

    /// Copies a temporary document-picker URL into Lore's private container.
    /// The returned value is relative so no temporary or sandbox-specific URL is persisted.
    func importEPUB(from sourceURL: URL, bookID: UUID) throws -> String {
        let fileManager = FileManager.default
        guard sourceURL.pathExtension.lowercased() == "epub" else {
            throw BookFileStoreError.unsupportedFileType
        }

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw BookFileStoreError.sourceUnavailable
        }

        let booksDirectory = applicationSupportURL.appendingPathComponent("Books", isDirectory: true)
        let bookDirectory = booksDirectory.appendingPathComponent(bookID.uuidString, isDirectory: true)
        let destinationURL = bookDirectory.appendingPathComponent("book.epub", isDirectory: false)

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw BookFileStoreError.destinationAlreadyExists
        }

        do {
            try fileManager.createDirectory(
                at: booksDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let stagingDirectory = booksDirectory.appendingPathComponent(
                ".import-\(UUID().uuidString)",
                isDirectory: true
            )
            let stagingURL = stagingDirectory.appendingPathComponent("book.epub")
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: false,
                attributes: nil
            )
            defer { try? fileManager.removeItem(at: stagingDirectory) }

            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            try fileManager.moveItem(at: stagingDirectory, to: bookDirectory)
            return relativePath(for: destinationURL)
        } catch let error as BookFileStoreError {
            throw error
        } catch {
            try? fileManager.removeItem(at: bookDirectory)
            throw BookFileStoreError.copyFailed
        }
    }

    func fileURL(for relativePath: String) throws -> URL {
        let fileManager = FileManager.default
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "Books",
              UUID(uuidString: String(components[1])) != nil,
              components[2] == "book.epub" else {
            throw BookFileStoreError.storedFileMissing
        }
        let standardizedRoot = applicationSupportURL.standardizedFileURL
        let candidate = standardizedRoot.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(standardizedRoot.path + "/"),
              fileManager.fileExists(atPath: candidate.path) else {
            throw BookFileStoreError.storedFileMissing
        }
        return candidate
    }

    func removeBookFile(at relativePath: String) throws {
        let fileURL = try fileURL(for: relativePath)
        try FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    private func relativePath(for url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(applicationSupportURL.standardizedFileURL.path.count + 1))
    }
}
