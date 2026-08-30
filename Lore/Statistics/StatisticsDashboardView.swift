import Observation
import SwiftUI

struct StatisticsDashboardView: View {
    @State private var model: StatisticsDashboardModel
    let onOpenLibrary: () -> Void

    init(adapter: StatisticsDataAdapter, onOpenLibrary: @escaping () -> Void) {
        _model = State(initialValue: StatisticsDashboardModel(adapter: adapter))
        self.onOpenLibrary = onOpenLibrary
    }

    var body: some View {
        StatisticsScreen(
            state: model.state,
            onRetry: model.load,
            onOpenLibrary: onOpenLibrary,
            onChangeMonth: model.changeMonth
        )
        .onAppear(perform: model.load)
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
