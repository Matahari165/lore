import SwiftData
import SwiftUI

@main
struct LoreApp: App {
    private let container: ModelContainer
    private let fileStore: BookFileStore

    init() {
        do {
            container = try ModelContainer(for: BookRecord.self)
            fileStore = try BookFileStore()
        } catch {
            fatalError("Impossible d’initialiser le stockage local : \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-statisticsPreview") {
                StatisticsScreen(state: .loaded(StatisticsPreviewData.snapshot))
            } else {
                LibraryView(
                    repository: BookRepository(context: container.mainContext),
                    fileStore: fileStore,
                    publicationService: ReadiumPublicationService()
                )
            }
        }
        .modelContainer(container)
    }
}
