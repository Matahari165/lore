import Observation
import SwiftUI

struct StatisticsDashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: StatisticsDashboardModel
    @State private var showsActivityChart = false
    let adapter: StatisticsDataAdapter
    let dailyGoalModel: DailyReadingGoalModel
    let refreshRevision: Int
    let onOpenLibrary: () -> Void

    init(
        adapter: StatisticsDataAdapter,
        dailyGoalModel: DailyReadingGoalModel,
        refreshRevision: Int = 0,
        onOpenLibrary: @escaping () -> Void
    ) {
        _model = State(initialValue: StatisticsDashboardModel(adapter: adapter))
        self.adapter = adapter
        self.dailyGoalModel = dailyGoalModel
        self.refreshRevision = refreshRevision
        self.onOpenLibrary = onOpenLibrary
    }

    var body: some View {
        StatisticsScreen(
            state: model.state,
            dailyGoalState: dailyGoalModel.state,
            onRetry: model.load,
            onOpenLibrary: onOpenLibrary,
            onOpenActivityChart: { showsActivityChart = true },
            onChangeMonth: model.changeMonth
        )
        .onAppear(perform: model.load)
        .onChange(of: refreshRevision) { _, _ in model.load() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            model.load()
        }
        .onChange(of: model.state) { _, state in
            if case let .loaded(snapshot) = state {
                dailyGoalModel.updateTodayDuration(snapshot.todayDuration)
            } else if case .empty = state {
                dailyGoalModel.updateTodayDuration(0)
            } else if case .failed = state {
                dailyGoalModel.markProgressUnavailable()
            }
        }
        .sheet(isPresented: $showsActivityChart) {
            ReadingActivityChartView(adapter: adapter)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

@MainActor
@Observable
private final class StatisticsDashboardModel {
    private let adapter: StatisticsDataAdapter
    private var referenceMonth = Date.now
    var state: StatisticsScreenState = .loading

    init(adapter: StatisticsDataAdapter) {
        self.adapter = adapter
    }

    func load() {
        do {
            let snapshot = try adapter.snapshot(containing: .now, referenceMonth: referenceMonth)
            let hasActivity = snapshot.todayDuration > 0
                || snapshot.weekDuration > 0
                || snapshot.monthDuration > 0
                || !snapshot.readingDays.isEmpty
                || !snapshot.inProgressBooks.isEmpty
                || !snapshot.finishedBooks.isEmpty
            state = hasActivity ? .loaded(snapshot) : .empty
        } catch {
            state = .failed(message: "Les statistiques ne sont pas disponibles pour le moment.")
        }
    }

    func changeMonth(by offset: Int) {
        guard let month = Calendar.autoupdatingCurrent.date(byAdding: .month, value: offset, to: referenceMonth) else { return }
        referenceMonth = month
        load()
    }
}
