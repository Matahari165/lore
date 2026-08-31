import Charts
import SwiftData
import SwiftUI

/// A focused page for the daily-goal shortcut. It reads the same local session
/// projection as Statistics, then lets the user switch between the current week
/// and month without changing the underlying data.
struct ReadingActivityChartView: View {
    let adapter: StatisticsDataAdapter

    @Environment(\.dismiss) private var dismiss
    @State private var range: ReadingActivityChartRange = .week
    @State private var state: ReadingActivityChartState = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView("Chargement de l’activité…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .loaded(points):
                    chartContent(points)
                case .empty:
                    ContentUnavailableView(
                        "Aucune lecture enregistrée",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Les minutes de lecture apparaîtront ici après une première session.")
                    )
                case .failed:
                    ContentUnavailableView {
                        Label("Activité indisponible", systemImage: "exclamationmark.circle")
                    } description: {
                        Text("Les minutes de lecture ne peuvent pas être chargées pour le moment.")
                    } actions: {
                        Button("Réessayer", action: load)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Minutes de lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer", action: dismiss.callAsFunction)
                }
            }
        }
        .loreCanvas()
        .task(id: range) { load() }
    }

    private func chartContent(_ points: [ReadingActivityPoint]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Picker("Période", selection: $range) {
                    ForEach(ReadingActivityChartRange.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Période du graphique")

                Text(range == .week ? "Cette semaine" : "Ce mois")
                    .font(.title3.weight(.semibold))

                Chart(points) { point in
                    BarMark(
                        x: .value("Jour", point.date, unit: .day),
                        y: .value("Minutes", point.duration / 60)
                    )
                    .foregroundStyle(LoreTheme.ink)
                    .cornerRadius(3)
                }
                .frame(height: 250)
                .chartYScale(domain: 0...maximumMinutes(in: points))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(LoreTheme.hairline)
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text("\(Int(minutes.rounded()))")
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.day().month(.abbreviated))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartAccessibilityLabel(points))

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(totalLabel(for: points))
                    Text(averageLabel(for: points))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LoreTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, LoreTheme.pageMargin)
            .padding(.bottom, 32)
        }
        .background(LoreTheme.canvas)
    }

    private func maximumMinutes(in points: [ReadingActivityPoint]) -> Double {
        let maximum = points.map { $0.duration / 60 }.max() ?? 0
        return max(10, ceil(maximum * 1.15 / 10) * 10)
    }

    private func totalLabel(for points: [ReadingActivityPoint]) -> String {
        let total = points.reduce(0) { $0 + $1.duration }
        return "Total : \(StatisticsFormat.accessibleDuration(total))"
    }

    private func averageLabel(for points: [ReadingActivityPoint], now: Date = .now) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let elapsedPoints = points.filter { $0.date <= today }
        let divisor = max(1, elapsedPoints.count)
        let total = elapsedPoints.reduce(0) { $0 + $1.duration }
        return "Moyenne : \(StatisticsFormat.accessibleDuration(total / Double(divisor)))/jour"
    }

    private func chartAccessibilityLabel(_ points: [ReadingActivityPoint]) -> String {
        guard !points.isEmpty else { return "Aucune minute de lecture" }
        let detail = points.map { point in
            let date = point.date.formatted(.dateTime.day().month(.wide))
            return "\(date), \(StatisticsFormat.accessibleDuration(point.duration))"
        }.joined(separator: ". ")
        return "\(averageLabel(for: points)). \(detail)"
    }

    private func load() {
        do {
            let points = try adapter.activityPoints(range: range, containing: .now)
            state = points.contains(where: { $0.duration > 0 }) ? .loaded(points) : .empty
        } catch {
            state = .failed
        }
    }
}

private enum ReadingActivityChartState: Equatable {
    case loading
    case loaded([ReadingActivityPoint])
    case empty
    case failed
}

#Preview("Graphique d’activité") {
    ReadingActivityChartView(adapter: StatisticsDataAdapter(context: try! ModelContainer(
        for: BookRecord.self, ReadingSessionRecord.self, HighlightRecord.self,
        AIConversationRecord.self, AIMessageRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ).mainContext))
}
