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
    func validateEPUBForImport(at fileURL: URL) async throws -> ImportedEPUBMetadata {
        let opened = try await openEPUB(at: fileURL)
        return ImportedEPUBMetadata(
            mediaType: opened.mediaType?.string ?? "application/epub+zip",
            title: opened.title,
            author: opened.author,
            coverData: opened.coverData
        )
    }

    func openEPUB(at fileURL: URL) async throws -> OpenedEPUB {
        guard fileURL.isFileURL, let readiumURL = FileURL(url: fileURL) else {
            throw ReaderError.invalidFileURL
        }

        do {
            // Readium's opening components are not Sendable. Keeping them local
            // prevents them from crossing the main-actor boundary under Swift 6.
            let httpClient = DefaultHTTPClient()
            let assetRetriever = AssetRetriever(httpClient: httpClient)
            let publicationOpener = PublicationOpener(
                parser: DefaultPublicationParser(
                    httpClient: httpClient,
                    assetRetriever: assetRetriever,
                    pdfFactory: DefaultPDFDocumentFactory()
                ),
                contentProtections: []
            )
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

            let cover = try? await publication.coverFitting(
                maxSize: CGSize(width: 1_200, height: 1_800)
            ).get()

            return OpenedEPUB(
                publication: publication,
                mediaType: asset.format.mediaType,
                title: publication.metadata.title,
                author: publication.metadata.authors
                    .map(\.name)
                    .joined(separator: ", ")
                    .nilIfEmpty,
                coverData: cover?.jpegData(compressionQuality: 0.88)
                    ?? cover?.pngData()
            )
        } catch let error as ReaderError {
            throw error
        } catch {
            throw ReaderError.openingFailed(error)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
