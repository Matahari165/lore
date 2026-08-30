import SwiftUI

struct AppRootView: View {
    enum Tab: Hashable {
        case library
        case statistics
    }

    @State private var selectedTab: Tab

    let bookRepository: BookRepository
    let sessionRepository: ReadingSessionRepository
    let statisticsAdapter: StatisticsDataAdapter
    let fileStore: BookFileStore
    let publicationService: ReadiumPublicationService

    init(
        initialTab: Tab = .library,
        bookRepository: BookRepository,
        sessionRepository: ReadingSessionRepository,
        statisticsAdapter: StatisticsDataAdapter,
        fileStore: BookFileStore,
        publicationService: ReadiumPublicationService
    ) {
        _selectedTab = State(initialValue: initialTab)
        self.bookRepository = bookRepository
        self.sessionRepository = sessionRepository
        self.statisticsAdapter = statisticsAdapter
        self.fileStore = fileStore
        self.publicationService = publicationService
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView(
                repository: bookRepository,
                sessionRepository: sessionRepository,
                fileStore: fileStore,
                publicationService: publicationService
            )
            .tabItem { Label("Bibliothèque", systemImage: "books.vertical") }
            .tag(Tab.library)

            StatisticsDashboardView(
                adapter: statisticsAdapter,
                onOpenLibrary: { selectedTab = .library }
            )
            .tabItem { Label("Statistiques", systemImage: "chart.bar.xaxis") }
            .tag(Tab.statistics)
        }
        .loreCanvas()
    }
}
