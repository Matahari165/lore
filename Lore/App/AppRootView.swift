import SwiftUI

struct AppRootView: View {
    enum Tab: Hashable {
        case home
        case library
        case statistics
    }

    @State private var selectedTab: Tab
    @State private var libraryModel: LibraryViewModel

    let statisticsAdapter: StatisticsDataAdapter

    init(
        initialTab: Tab = .home,
        bookRepository: BookRepository,
        sessionRepository: ReadingSessionRepository,
        statisticsAdapter: StatisticsDataAdapter,
        fileStore: BookFileStore,
        publicationService: ReadiumPublicationService
    ) {
        _selectedTab = State(initialValue: initialTab)
        _libraryModel = State(initialValue: LibraryViewModel(
            repository: bookRepository,
            sessionRepository: sessionRepository,
            fileStore: fileStore,
            publicationService: publicationService
        ))
        self.statisticsAdapter = statisticsAdapter
    }

    var body: some View {
        @Bindable var libraryModel = libraryModel

        TabView(selection: $selectedTab) {
            LibraryView(
                mode: .home,
                model: libraryModel
            )
            .tabItem { Label("Accueil", systemImage: "house") }
            .tag(Tab.home)

            LibraryView(
                mode: .library,
                model: libraryModel
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
        .alert("Importation terminée", isPresented: Binding(
            get: { libraryModel.importSummary != nil },
            set: { if !$0 { libraryModel.importSummary = nil } }
        )) {
            Button("OK", role: .cancel) { libraryModel.importSummary = nil }
        } message: {
            Text(libraryModel.importSummary?.message ?? "")
        }
        .alert("Impossible de continuer", isPresented: Binding(
            get: { libraryModel.errorMessage != nil },
            set: { if !$0 { libraryModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { libraryModel.errorMessage = nil }
        } message: {
            Text(libraryModel.errorMessage ?? "")
        }
        .fullScreenCover(item: $libraryModel.readerPresentation) { presentation in
            ReaderScreen(presentation: presentation) {
                await libraryModel.closeReader()
            }
        }
    }
}
