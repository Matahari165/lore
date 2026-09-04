import Foundation

enum EPUBImportSourceResolverError: LocalizedError, Equatable {
    case tooManyFiles(limit: Int)

    var errorDescription: String? {
        switch self {
        case let .tooManyFiles(limit):
            "Ce dossier contient plus de \(limit) EPUB. Choisissez un dossier plus petit."
        }
    }
}

enum EPUBImportSourceResolver {
    static let maximumFileCount = 500

    static func epubURLs(
        from sourceURL: URL,
        fileManager: FileManager = .default,
        maximumFileCount: Int = maximumFileCount
    ) throws -> [URL] {
        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            guard let enumerator = fileManager.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw BookFileStoreError.sourceUnavailable
            }
            var urls: [URL] = []
            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("epub") == .orderedSame,
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else { continue }
                guard urls.count < maximumFileCount else {
                    throw EPUBImportSourceResolverError.tooManyFiles(limit: maximumFileCount)
                }
                urls.append(url)
            }
            return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }

        guard values.isRegularFile == true,
              sourceURL.pathExtension.caseInsensitiveCompare("epub") == .orderedSame
        else {
            throw BookFileStoreError.unsupportedFileType
        }
        return [sourceURL]
    }
}
