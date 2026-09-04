import Foundation
import ReadiumShared
import ReadiumStreamer
import UIKit

struct OpenedEPUB {
    let publication: Publication
    let mediaType: MediaType?
    let title: String?
    let author: String?
    let coverData: Data?
}

/// Identifies the exact on-disk version of an imported EPUB.
///
/// Imported books are promoted atomically and are not edited in place. Using
/// the path, byte count and modification date keeps the cache cheap while
/// invalidating it whenever a different file is installed at the same path.
struct ReadiumPublicationCacheKey: Hashable, Sendable {
    let standardizedPath: String
    let fileSize: Int64
    let modificationDate: Date
}

struct ImportedEPUBMetadata: Sendable, Equatable {
    let mediaType: String
    let title: String?
    let author: String?
    let coverData: Data?
}

@MainActor
protocol EPUBImportValidating: AnyObject {
    func validateEPUBForImport(at fileURL: URL) async throws -> ImportedEPUBMetadata
}

/// Owns the long-lived Readium opening dependencies. Lore supplies no content
/// protection, so a restricted publication is rejected instead of prompting.
@MainActor
final class ReadiumPublicationService: EPUBImportValidating {
    private let httpClient: DefaultHTTPClient
    // Readium does not yet annotate these reference types as Sendable. The
    // service itself is MainActor-isolated, so every access remains serialized.
    nonisolated(unsafe) private let assetRetriever: AssetRetriever
    nonisolated(unsafe) private let publicationOpener: PublicationOpener
    private let cacheCapacity: Int
    private var publicationCache: [ReadiumPublicationCacheKey: OpenedEPUB] = [:]
    private var cacheRecency: [ReadiumPublicationCacheKey: UInt64] = [:]
    private var nextRecency: UInt64 = 0
    private var memoryWarningTask: Task<Void, Never>?

    /// These counters are intentionally observable for diagnostics and tests:
    /// opening the same immutable imported file twice should produce one miss
    /// followed by a cache hit.
    private(set) var cacheHits = 0
    private(set) var cacheMisses = 0

    init(cacheCapacity: Int = 2) {
        self.cacheCapacity = max(cacheCapacity, 1)
        let httpClient = DefaultHTTPClient()
        self.httpClient = httpClient
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        self.assetRetriever = assetRetriever
        self.publicationOpener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            ),
            contentProtections: []
        )
        memoryWarningTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didReceiveMemoryWarningNotification
            ) {
                guard let self else { return }
                clearCache()
            }
        }
    }

    deinit {
        memoryWarningTask?.cancel()
    }

    func validateEPUBForImport(at fileURL: URL) async throws -> ImportedEPUBMetadata {
        let opened = try await openEPUB(at: fileURL)
        // Cover extraction decodes and resizes an image. It is useful once at
        // import time, but doing it again every time the reader opens would
        // delay the first rendered page for data already stored in BookRecord.
        nonisolated(unsafe) let publication = opened.publication
        let cover = try? await publication.coverFitting(
            maxSize: CGSize(width: 1_200, height: 1_800)
        ).get()
        return ImportedEPUBMetadata(
            mediaType: opened.mediaType?.string ?? "application/epub+zip",
            title: opened.title,
            author: opened.author,
            coverData: cover?.jpegData(compressionQuality: 0.88)
                ?? cover?.pngData()
        )
    }

    func openEPUB(at fileURL: URL) async throws -> OpenedEPUB {
        guard fileURL.isFileURL, let readiumURL = FileURL(url: fileURL) else {
            throw ReaderError.invalidFileURL
        }

        let cacheKey = cacheKey(for: fileURL)
        if let cacheKey, let cached = publicationCache[cacheKey] {
            markCacheUse(for: cacheKey)
            cacheHits += 1
            return cached
        }
        cacheMisses += 1

        do {
            let asset = try await assetRetriever.retrieve(url: readiumURL).get()
            let publication = try await publicationOpener.open(
                asset: asset,
                allowUserInteraction: false
            ).get()

            guard publication.conforms(to: .epub) else {
                throw ReaderError.unsupportedPublication
            }
            guard !publication.isRestricted else {
                throw ReaderError.restrictedPublication
            }

            let opened = OpenedEPUB(
                publication: publication,
                mediaType: asset.format.mediaType,
                title: publication.metadata.title,
                author: publication.metadata.authors
                    .map(\.name)
                    .joined(separator: ", ")
                    .nilIfEmpty,
                // ReaderSessionController only needs the parsed publication.
                // The imported cover already lives in BookRecord.
                coverData: nil
            )
            if let cacheKey {
                publicationCache[cacheKey] = opened
                markCacheUse(for: cacheKey)
                trimCacheIfNeeded()
            }
            return opened
        } catch let error as ReaderError {
            throw error
        } catch {
            throw ReaderError.openingFailed(error)
        }
    }

    /// Drops all retained Readium publications. The next open will parse the
    /// EPUB again, which is useful after a memory warning or in tests.
    func clearCache() {
        publicationCache.removeAll(keepingCapacity: true)
        cacheRecency.removeAll(keepingCapacity: true)
        nextRecency = 0
    }

    private func cacheKey(for fileURL: URL) -> ReadiumPublicationCacheKey? {
        let standardizedURL = fileURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else { return nil }
        guard let values = try? standardizedURL.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
        ]), let fileSize = values.fileSize,
              let modificationDate = values.contentModificationDate else {
            return nil
        }
        return ReadiumPublicationCacheKey(
            standardizedPath: standardizedURL.path,
            fileSize: Int64(fileSize),
            modificationDate: modificationDate
        )
    }

    private func markCacheUse(for key: ReadiumPublicationCacheKey) {
        nextRecency &+= 1
        cacheRecency[key] = nextRecency
    }

    private func trimCacheIfNeeded() {
        guard publicationCache.count > cacheCapacity else { return }
        let staleKeys = publicationCache.keys
            .sorted { (cacheRecency[$0] ?? 0) < (cacheRecency[$1] ?? 0) }
            .dropLast(cacheCapacity)
        for key in staleKeys {
            publicationCache.removeValue(forKey: key)
            cacheRecency.removeValue(forKey: key)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
