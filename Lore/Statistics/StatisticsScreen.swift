import SwiftUI
import UIKit

struct StatisticsScreen: View {
    let state: StatisticsScreenState
    var dailyGoalState: DailyGoalState = .disabled
    var onRetry: () -> Void = {}
    var onOpenLibrary: () -> Void = {}
    var onOpenActivityChart: () -> Void = {}
    var onChangeMonth: (Int) -> Void = { _ in }
    var onSelectBook: (StatisticsBookSummary) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    loadingContent
                case let .loaded(snapshot):
                    StatisticsContent(
                        snapshot: snapshot,
                        dailyGoalState: dailyGoalState,
                        onOpenActivityChart: onOpenActivityChart,
                        onChangeMonth: onChangeMonth,
                        onSelectBook: onSelectBook
                    )
                case .empty:
                    emptyContent
                case let .failed(message):
                    errorContent(message)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Activité")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .loreCanvas()
    }

    private var loadingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                StatisticsMetrics(
                    today: 38 * 60,
                    week: 4 * 60 * 60,
                    month: 13 * 60 * 60
                )
                CalendarPlaceholder()
                BookListPlaceholder(title: "En cours")
            }
            .redacted(reason: .placeholder)
            .padding(.horizontal, LoreTheme.pageMargin)
            .padding(.bottom, 32)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement de l’activité")
    }

    private var emptyContent: some View {
        VStack(spacing: 16) {
            DailyGoalProgressView(state: dailyGoalState, onTap: onOpenActivityChart)
                .padding(.horizontal, LoreTheme.pageMargin)
            ContentUnavailableView {
                Label("Aucune lecture enregistrée", systemImage: "clock")
            } description: {
                Text("Votre activité apparaîtra ici après une première session de lecture.")
            } actions: {
                Button("Ouvrir la bibliothèque", action: onOpenLibrary)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(LoreTheme.canvas)
                    .controlSize(.large)
            }
        }
    }

    private func errorContent(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Activité indisponible", systemImage: "exclamationmark.circle")
        } description: {
            Text(message)
        } actions: {
            Button("Réessayer", action: onRetry)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(LoreTheme.canvas)
                .controlSize(.large)
        }
    }
}

private struct StatisticsContent: View {
    let snapshot: StatisticsSnapshot
    let dailyGoalState: DailyGoalState
    let onOpenActivityChart: () -> Void
    let onChangeMonth: (Int) -> Void
    let onSelectBook: (StatisticsBookSummary) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                DailyGoalProgressView(state: dailyGoalState, onTap: onOpenActivityChart)
                StatisticsMetrics(
                    today: snapshot.todayDuration,
                    week: snapshot.weekDuration,
                    month: snapshot.monthDuration
                )

                ReadingCalendar(
                    month: snapshot.referenceMonth,
                    readingDays: snapshot.readingDays,
                    onChangeMonth: onChangeMonth
                )

                FinishedBooksSinceYearStart(
                    books: snapshot.finishedBooks,
                    onSelectBook: onSelectBook
                )

                if !snapshot.inProgressBooks.isEmpty {
                    StatisticsBookList(
                        title: "En cours",
                        books: snapshot.inProgressBooks,
                        onSelectBook: onSelectBook
                    )
                }

            }
            .padding(.horizontal, LoreTheme.pageMargin)
            .padding(.bottom, 32)
        }
        .background(LoreTheme.canvas)
    }
}

private struct FinishedBooksSinceYearStart: View {
    let books: [StatisticsBookSummary]
    let onSelectBook: (StatisticsBookSummary) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    private var booksReadSinceJanuary2026: [StatisticsBookSummary] {
        let calendar = Calendar.autoupdatingCurrent
        return books
            .filter { book in
                let year = book.readingYear
                    ?? book.finishedAt.map { calendar.component(.year, from: $0) }
                return (year ?? 0) >= 2026
            }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    @ViewBuilder
    var body: some View {
        if !booksReadSinceJanuary2026.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Livres lus depuis janvier 2026")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(booksReadSinceJanuary2026) { book in
                        Button { onSelectBook(book) } label: {
                            StatisticsBookCover(book: book)
                                .frame(width: 88)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(coverAccessibilityLabel(for: book))
                    }
                }
            }
        }
    }

    private func coverAccessibilityLabel(for book: StatisticsBookSummary) -> String {
        var values = [book.title]
        if let author = book.author { values.append(author) }
        if let date = book.finishedAt {
            values.append("Lu le \(date.formatted(.dateTime.day().month(.wide).year()))")
        }
        return values.joined(separator: ", ")
    }
}

private struct StatisticsMetrics: View {
    let today: TimeInterval
    let week: TimeInterval
    let month: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Temps de lecture")
                .font(.title3.weight(.semibold))

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    metric("Aujourd’hui", duration: today)
                    divider
                    metric("Cette semaine", duration: week)
                    divider
                    metric("Ce mois", duration: month)
                }

                VStack(alignment: .leading, spacing: 12) {
                    metric("Aujourd’hui", duration: today)
                    metric("Cette semaine", duration: week)
                    metric("Ce mois", duration: month)
                }
            }
        }
    }

    private func metric(_ label: String, duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(StatisticsFormat.duration(duration))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(LoreTheme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(LoreTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(StatisticsFormat.accessibleDuration(duration))")
    }

    private var divider: some View {
        Rectangle()
            .fill(LoreTheme.hairline)
            .frame(width: 1, height: 48)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)
    }
}

private struct ReadingCalendar: View {
    let month: Date
    let readingDays: [ReadingDaySummary]
    let onChangeMonth: (Int) -> Void

    @State private var selectedDate: Date?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calendrier")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Mois précédent", systemImage: "chevron.left") {
                    selectedDate = nil
                    onChangeMonth(-1)
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                Button("Mois suivant", systemImage: "chevron.right") {
                    selectedDate = nil
                    onChangeMonth(1)
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
            }

            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LoreTheme.secondaryInk)

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LoreTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .accessibilityHidden(true)
                }

                ForEach(calendarCells) { cell in
                    if let date = cell.date {
                        dayButton(date)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }

            if let selectedDate {
                let duration = duration(on: selectedDate)
                Text("\(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(StatisticsFormat.accessibleDuration(duration))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(duration > 0 ? LoreTheme.ink : LoreTheme.secondaryInk)
                    .accessibilityAddTraits(.isSummaryElement)
            } else {
                Text(calendarSummary)
                    .font(.footnote)
                    .foregroundStyle(LoreTheme.secondaryInk)
                    .accessibilityAddTraits(.isSummaryElement)
            }
        }
        .padding(.top, 2)
    }

    private func dayButton(_ date: Date) -> some View {
        let dayDuration = duration(on: date)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false

        return Button {
            selectedDate = date
        } label: {
            ZStack {
                Circle()
                    .fill(dayDuration > 0 ? LoreTheme.ink.opacity(intensity(for: dayDuration)) : .clear)
                    .overlay {
                        if isSelected {
                            Circle().stroke(LoreTheme.ink, lineWidth: 2)
                        }
                    }
                    .frame(width: 34, height: 34)
                Text(date.formatted(.dateTime.day()))
                    .font(.caption.weight(dayDuration > 0 ? .semibold : .regular))
                    .foregroundStyle(dayDuration > 0 ? LoreTheme.canvas : LoreTheme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(StatisticsFormat.accessibleDuration(dayDuration))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var calendarSummary: String {
        let activeDays = readingDays.filter { $0.duration > 0 }.count
        let total = readingDays.reduce(0) { $0 + $1.duration }
        return "\(activeDays) jours de lecture · \(StatisticsFormat.accessibleDuration(total))"
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(0, calendar.firstWeekday - 1)
        return Array(symbols[start...] + symbols[..<start])
    }

    private var calendarCells: [CalendarCell] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let dayRange = calendar.range(of: .day, in: .month, for: month)
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dated = dayRange.compactMap { day -> CalendarCell? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) else { return nil }
            return CalendarCell(id: day + leading, date: date)
        }
        let leadingCells = (0..<leading).map { CalendarCell(id: $0, date: nil) }
        return leadingCells + dated
    }

    private func duration(on date: Date) -> TimeInterval {
        readingDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.duration ?? 0
    }

    private func intensity(for duration: TimeInterval) -> Double {
        min(1, 0.72 + duration / 14_400)
    }
}

private struct CalendarCell: Identifiable {
    let id: Int
    let date: Date?
}

private struct StatisticsBookList: View {
    let title: String
    let books: [StatisticsBookSummary]
    let onSelectBook: (StatisticsBookSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(spacing: 0) {
                ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                    if index > 0 {
                        Divider().overlay(LoreTheme.hairline)
                    }
                    Button {
                        onSelectBook(book)
                    } label: {
                        StatisticsBookRow(book: book)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StatisticsBookRow: View {
    let book: StatisticsBookSummary

    var body: some View {
        HStack(spacing: 14) {
            StatisticsBookCover(book: book)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(LoreTheme.ink)
                    .lineLimit(2)
                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(LoreTheme.secondaryInk)
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LoreTheme.secondaryInk)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoreTheme.secondaryInk)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var detail: String {
        if let finishedAt = book.finishedAt {
            let date = finishedAt.formatted(.dateTime.day().month(.wide))
            if let rating = book.rating { return "Terminé le \(date) · \(rating)/10" }
            return "Terminé le \(date)"
        }
        if let progress = book.progress {
            let progressText = progress.formatted(.percent.precision(.fractionLength(0)))
            if let startedAt = book.startedAt {
                return "\(progressText) · Commencé le \(startedAt.formatted(.dateTime.day().month(.wide)))"
            }
            return progressText
        }
        return "En cours"
    }

    private var accessibilityLabel: String {
        [book.title, book.author, detail].compactMap { $0 }.joined(separator: ", ")
    }
}

private struct StatisticsBookCover: View {
    let book: StatisticsBookSummary

    var body: some View {
        BookCoverView(coverData: book.coverData, title: book.title)
    }
}

private struct CalendarPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendrier").font(.title3.weight(.semibold))
            Text("Août 2026").font(.subheadline)
            Rectangle()
                .fill(LoreTheme.hairline)
                .frame(height: 250)
        }
    }
}

private struct BookListPlaceholder: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.semibold))
            ForEach(0..<2) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: LoreTheme.coverRadius).frame(width: 48, height: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Titre du livre").font(.headline)
                        Text("Nom de l’auteur").font(.subheadline)
                    }
                }
            }
        }
    }
}

enum StatisticsFormat {
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        if remainder == 0 { return "\(hours) h" }
        return "\(hours) h \(remainder) min"
    }

    static func accessibleDuration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        if minutes == 0 { return "aucune minute de lecture" }
        if hours == 0 { return "\(remainder) minutes de lecture" }
        if remainder == 0 { return "\(hours) heures de lecture" }
        return "\(hours) heures et \(remainder) minutes de lecture"
    }
}

#Preview("Données") {
    StatisticsScreen(state: .loaded(StatisticsPreviewData.snapshot))
}

#Preview("Vide") {
    StatisticsScreen(state: .empty)
}

#Preview("Chargement") {
    StatisticsScreen(state: .loading)
}

#Preview("Erreur") {
    StatisticsScreen(state: .failed(message: "Les statistiques ne sont pas disponibles pour le moment."))
}
