import SwiftUI

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    enum Tab: Hashable {
        case home
        case library
        case statistics
        case podcasts
    }

    @State private var selectedTab: Tab
    @State private var libraryModel: LibraryViewModel
    @State private var dailyGoalModel: DailyReadingGoalModel
    @State private var presentsSettings = false
    @State private var presentsActivityChart = false
    @State private var statisticsRevision = 0
    @State private var podcastModel: PodcastLibraryModel
    @State private var goalNotifier = DailyGoalNotifier()
    @State private var showsGoalNotificationPrompt = false
    @State private var didPromptGoalNotifications = false

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
        podcastRepository: PodcastRepository,
        podcastFileStore: PodcastFileStore,
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
        _podcastModel = State(initialValue: PodcastLibraryModel(
            repository: podcastRepository,
            fileStore: podcastFileStore
        ))
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
                    onOpenActivityChart: { presentsActivityChart = true },
                    onOpenHighlight: openHighlight,
                    onOpenDiscussionSource: openDiscussionSource
                )
                .tabItem { Label("Accueil", systemImage: "house") }
                .tag(Tab.home)

                LibraryView(
                    mode: .library,
                    model: libraryModel,
                    onOpenHighlight: openHighlight,
                    onOpenDiscussionSource: openDiscussionSource
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

                PodcastLibraryView(model: podcastModel)
                    .tabItem { Label("Podcasts", systemImage: "waveform") }
                    .tag(Tab.podcasts)
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
                } onReadingProgress: {
                    reloadDailyGoal()
                }
                .zIndex(1)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            reloadDailyGoal()
            await libraryModel.loadYesterdayAIRecapIfNeeded(force: true)
        }
        .onChange(of: selectedTab) { _, _ in reloadDailyGoal() }
        .onOpenURL { url in
            Task { await libraryModel.importURLs([url]) }
        }
        .sheet(isPresented: $presentsSettings, onDismiss: reloadDailyGoal) {
            SettingsView(model: dailyGoalModel) {
                let count = try sessionRepository.clearSessions(on: .now)
                statisticsRevision += 1
                reloadDailyGoal()
                return count
            }
        }
        .sheet(isPresented: $presentsActivityChart) {
            ReadingActivityChartView(
                adapter: statisticsAdapter,
                targetMinutes: dailyGoalModel.minutes
            )
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
        .alert("Notifications de lecture", isPresented: $showsGoalNotificationPrompt) {
            Button("Activer") {
                Task {
                    await goalNotifier.requestAuthorizationIfNeeded()
                    await refreshGoalNotifications()
                }
            }
            Button("Plus tard", role: .cancel) {}
        } message: {
            Text("Lore vous prévient quand votre objectif quotidien est atteint et vous rappelle à 21 h si l’objectif n’est pas atteint. Les notifications ne contiennent que des durées, jamais vos livres.")
        }
    }

    private func openHighlight(_ book: BookRecord, _ highlight: ReaderHighlight) {
        selectedTab = .library
        Task { await libraryModel.open(book, at: highlight) }
    }

    private func reloadDailyGoal() {
        dailyGoalModel.reload()
        do {
            dailyGoalModel.updateTodayDuration(
                try statisticsAdapter.snapshot(containing: .now).todayDuration
            )
            if let targetMinutes = dailyGoalModel.minutes {
                dailyGoalModel.updateStreak(try statisticsAdapter.goalStreak(
                    targetMinutes: targetMinutes,
                    containing: .now
                ))
            } else {
                dailyGoalModel.updateStreak(.empty)
            }
        } catch {
            dailyGoalModel.markProgressUnavailable()
        }
        handleGoalNotifications()
    }

    /// Déclencheur des notifications : appelé au lancement (tâche `scenePhase`),
    /// au changement d'onglet, à la fermeture des réglages et après fermeture du lecteur.
    private func handleGoalNotifications() {
        switch dailyGoalModel.state {
        case .active(let progress):
            let targetMinutes = progress.targetMinutes
            let readSeconds = progress.readSeconds
            Task {
                await refreshGoalNotifications(targetMinutes: targetMinutes, readSeconds: readSeconds)
                guard !didPromptGoalNotifications else { return }
                let status = await goalNotifier.authorizationStatus()
                if status == .notDetermined {
                    didPromptGoalNotifications = true
                    showsGoalNotificationPrompt = true
                }
            }
        case .disabled, .failed:
            Task { await goalNotifier.refreshGoalState(targetMinutes: nil, todayDuration: 0) }
        }
    }

    private func refreshGoalNotifications(targetMinutes: Int? = nil, readSeconds: TimeInterval = 0) async {
        if let targetMinutes {
            await goalNotifier.refreshGoalState(targetMinutes: targetMinutes, todayDuration: readSeconds)
            return
        }
        switch dailyGoalModel.state {
        case .active(let progress):
            await goalNotifier.refreshGoalState(
                targetMinutes: progress.targetMinutes,
                todayDuration: progress.readSeconds
            )
        case .disabled, .failed:
            await goalNotifier.refreshGoalState(targetMinutes: nil, todayDuration: 0)
        }
    }

    private func openDiscussionSource(book: BookRecord, source: LoreAIChatSource) {
        Task { @MainActor in
            await libraryModel.open(book)
            guard let presentation = libraryModel.readerPresentation,
                  await presentation.session.go(to: source)
            else {
                libraryModel.errorMessage = "Le passage cité n’est plus disponible dans ce livre."
                return
            }
        }
    }
}
