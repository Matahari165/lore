import SwiftData
import SwiftUI

@main
struct LoreApp: App {
    private let container: ModelContainer
    private let fileStore: BookFileStore

    init() {
        do {
            container = try ModelContainer(for: BookRecord.self, ReadingSessionRecord.self)
            fileStore = try BookFileStore()
            let sessions = ReadingSessionRepository(context: container.mainContext)
            try sessions.recoverOpenSessions(now: .now)
        } catch {
            fatalError("Impossible d’initialiser le stockage local : \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(
                repository: BookRepository(context: container.mainContext),
                sessionRepository: ReadingSessionRepository(context: container.mainContext),
                fileStore: fileStore,
                publicationService: ReadiumPublicationService()
            )
        }
        .modelContainer(container)
    }
}
