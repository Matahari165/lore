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
            let localSchema = Schema([
                BookRecord.self,
                ReadingSessionRecord.self,
                HighlightRecord.self,
                VocabularyRecord.self,
                AIConversationRecord.self,
                AIMessageRecord.self,
                PodcastRecord.self,
                ManualCollectionRecord.self,
                CollectionMembershipRecord.self
            ])
            let localConfiguration = ModelConfiguration(schema: localSchema, cloudKitDatabase: .none)
            container = try ModelContainer(for: localSchema, configurations: localConfiguration)
            fileStore = try BookFileStore()
            podcastFileStore = try PodcastFileStore()
            let sessions = ReadingSessionRepository(context: container.mainContext)
            try sessions.recoverOpenSessions(now: .now)
            // Les rappels restent visibles au premier plan, sauf si le mode de
            // concentration interne est actif pendant la lecture.
            UNUserNotificationCenter.current().delegate = DailyGoalForegroundDelegate.shared
        } catch {
            fatalError("Impossible d’initialiser le stockage local : \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            // Lore utilise une identité sombre unique sur tous ses écrans, y compris
            // les feuilles et les contrôles système présentés par SwiftUI.
            .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
