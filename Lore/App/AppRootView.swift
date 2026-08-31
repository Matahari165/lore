import SwiftUI

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    enum Tab: Hashable {
        case home
        case library
        case statistics
    }

    @State private var selectedTab: Tab
    @State private var libraryModel: LibraryViewModel
    @State private var dailyGoalModel: DailyReadingGoalModel
    @State private var presentsSettings = false
    @State private var presentsActivityChart = false
    @State private var statisticsRevision = 0

    let statisticsAdapter: StatisticsDataAdapter
    let sessionRepository: ReadingSessionRepository
    let conversationRepository: AIConversationRepository

    init(
        initialTab: Tab = .home,
        bookRepository: BookRepository,
        sessionRepository: ReadingSessionRepository,
        statisticsAdapter: StatisticsDataAdapter,
        fileStore: BookFileStore,
        publicationService: ReadiumPublicationService,
        conversationRepository: AIConversationRepository,
        dailyGoalStore: any DailyReadingGoalStore = UserDefaultsDailyReadingGoalStore()
    ) {
        _selectedTab = State(initialValue: initialTab)
        _libraryModel = State(initialValue: LibraryViewModel(
            repository: bookRepository,
            sessionRepository: sessionRepository,
            fileStore: fileStore,
            publicationService: publicationService,
            conversationRepository: conversationRepository
        ))
        _dailyGoalModel = State(initialValue: DailyReadingGoalModel(store: dailyGoalStore))
        self.statisticsAdapter = statisticsAdapter
        self.sessionRepository = sessionRepository
        self.conversationRepository = conversationRepository
    }

    var body: some View {
        @Bindable var libraryModel = libraryModel

        ZStack {
            TabView(selection: $selectedTab) {
                LibraryView(
                    mode: .home,
                    model: libraryModel,
                    dailyGoalState: dailyGoalModel.state,
                    onOpenSettings: { presentsSettings = true },
                    onOpenActivityChart: { presentsActivityChart = true }
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
                    dailyGoalModel: dailyGoalModel,
                    refreshRevision: statisticsRevision,
                    onOpenLibrary: { selectedTab = .library }
                )
                .tabItem { Label("Statistiques", systemImage: "chart.bar.xaxis") }
                .tag(Tab.statistics)
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .loreCanvas()
            .allowsHitTesting(libraryModel.readerPresentation == nil)
            .accessibilityHidden(libraryModel.readerPresentation != nil)

            if let presentation = libraryModel.readerPresentation {
                ReaderScreen(presentation: presentation) {
                    await libraryModel.closeReader()
                    if libraryModel.readerPresentation == nil {
                        reloadDailyGoal()
                    }
                }
                .zIndex(1)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            reloadDailyGoal()
        }
        .onChange(of: selectedTab) { _, _ in reloadDailyGoal() }
        .sheet(isPresented: $presentsSettings, onDismiss: reloadDailyGoal) {
            SettingsView(model: dailyGoalModel) {
                let count = try sessionRepository.clearSessions(on: .now)
                statisticsRevision += 1
                reloadDailyGoal()
                return count
            }
        }
        .sheet(isPresented: $presentsActivityChart) {
            ReadingActivityChartView(adapter: statisticsAdapter)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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
    }

    private func reloadDailyGoal() {
        dailyGoalModel.reload()
        do {
            dailyGoalModel.updateTodayDuration(
                try statisticsAdapter.snapshot(containing: .now).todayDuration
            )
        } catch {
            dailyGoalModel.markProgressUnavailable()
        }
    }
}
