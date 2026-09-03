import Foundation
import Observation

@MainActor
@Observable
final class PodcastLibraryModel {
    struct ImportIssue: Identifiable, Equatable {
        let id = UUID()
        let filename: String
        let message: String
    }

    struct ImportSummary: Equatable {
        var imported = 0
        var duplicates = 0
        var issues: [ImportIssue] = []

        var message: String {
            var lines = ["\(imported) importé(s), \(duplicates) déjà présent(s)."]
            if !issues.isEmpty {
                lines.append(contentsOf: issues.map { "\($0.filename) : \($0.message)" })
            }
            return lines.joined(separator: "\n")
        }
    }

    let repository: PodcastRepository
    let fileStore: PodcastFileStore
    private let importService: PodcastImportService

    var podcasts: [PodcastRecord] = []
    var isImporting = false
    var importSummary: ImportSummary?
    var errorMessage: String?

    init(repository: PodcastRepository, fileStore: PodcastFileStore) {
        self.repository = repository
        self.fileStore = fileStore
        importService = PodcastImportService(repository: repository, fileStore: fileStore)
        reload()
    }

    func reload() {
        do {
            podcasts = try repository.podcasts()
        } catch {
            present(error)
        }
    }

    func importSelection(_ result: Result<[URL], Error>) async {
        guard !isImporting else { return }
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { throw CocoaError(.fileNoSuchFile) }
            isImporting = true
            defer { isImporting = false }
            var summary = ImportSummary()
            for url in urls {
                do {
                    switch try await importService.importMP4(from: url) {
                    case .imported: summary.imported += 1
                    case .alreadyImported: summary.duplicates += 1
                    }
                } catch {
                    summary.issues.append(ImportIssue(
                        filename: url.lastPathComponent,
                        message: (error as? LocalizedError)?.errorDescription ?? "Import impossible"
                    ))
                }
            }
            reload()
            importSummary = summary
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
