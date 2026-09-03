import SwiftData
import SwiftUI
import UserNotifications

@main
struct LoreApp: App {
    private let container: ModelContainer
    private let fileStore: BookFileStore
    private let podcastFileStore: PodcastFileStore

    init() {
        do {
            container = try ModelContainer(
                for: BookRecord.self,
                ReadingSessionRecord.self,
                HighlightRecord.self,
                VocabularyRecord.self,
                AIConversationRecord.self,
                AIMessageRecord.self,
                PodcastRecord.self
            )
            fileStore = try BookFileStore()
            podcastFileStore = try PodcastFileStore()
            let sessions = ReadingSessionRepository(context: container.mainContext)
            try sessions.recoverOpenSessions(now: .now)
            // Bannière + son même quand Lore est au premier plan (notifications d'objectif).
            UNUserNotificationCenter.current().delegate = DailyGoalForegroundDelegate.shared
        } catch {
            fatalError("Impossible d’initialiser le stockage local : \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-statisticsPreview") {
                StatisticsScreen(state: .loaded(StatisticsPreviewData.snapshot))
            } else {
                let conversations = AIConversationRepository(context: container.mainContext)
                let vocabulary = VocabularyRepository(context: container.mainContext)
                let books = BookRepository(
                    context: container.mainContext,
                    conversationRepository: conversations,
                    vocabularyRepository: vocabulary
                )
                let sessions = ReadingSessionRepository(context: container.mainContext)
                let podcasts = PodcastRepository(context: container.mainContext)
                AppRootView(
                    initialTab: ProcessInfo.processInfo.arguments.contains("-statisticsTab") ? .statistics : .home,
                    bookRepository: books,
                    sessionRepository: sessions,
                    statisticsAdapter: StatisticsDataAdapter(context: container.mainContext),
                    fileStore: fileStore,
                    publicationService: ReadiumPublicationService(),
                    conversationRepository: conversations,
                    podcastRepository: podcasts,
                    podcastFileStore: podcastFileStore
                )
            }
        }
        .modelContainer(container)
    }
}
