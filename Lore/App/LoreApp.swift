import SwiftData
import SwiftUI

@main
struct LoreApp: App {
    private let container: ModelContainer
    private let fileStore: BookFileStore

    init() {
        do {
            container = try ModelContainer(for: BookRecord.self, ReadingSessionRecord.self, HighlightRecord.self)
            fileStore = try BookFileStore()
            let sessions = ReadingSessionRepository(context: container.mainContext)
            try sessions.recoverOpenSessions(now: .now)
        } catch {
            fatalError("Impossible d’initialiser le stockage local : \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-statisticsPreview") {
                StatisticsScreen(state: .loaded(StatisticsPreviewData.snapshot))
            } else {
                let books = BookRepository(context: container.mainContext)
                let sessions = ReadingSessionRepository(context: container.mainContext)
                AppRootView(
                    initialTab: ProcessInfo.processInfo.arguments.contains("-statisticsTab") ? .statistics : .home,
                    bookRepository: books,
                    sessionRepository: sessions,
                    statisticsAdapter: StatisticsDataAdapter(context: container.mainContext),
                    fileStore: fileStore,
                    publicationService: ReadiumPublicationService()
                )
            }
        }
        .modelContainer(container)
    }
}
