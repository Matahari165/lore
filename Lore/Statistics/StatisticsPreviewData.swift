import Foundation

enum StatisticsPreviewData {
    private static let calendar = Calendar(identifier: .gregorian)

    static let snapshot = StatisticsSnapshot(
        referenceMonth: date(2026, 8, 1),
        todayDuration: 38 * 60,
        weekDuration: (4 * 60 + 12) * 60,
        monthDuration: (13 * 60 + 47) * 60,
        readingDays: [
            ReadingDaySummary(date: date(2026, 8, 2), duration: 18 * 60),
            ReadingDaySummary(date: date(2026, 8, 4), duration: 42 * 60),
            ReadingDaySummary(date: date(2026, 8, 5), duration: 27 * 60),
            ReadingDaySummary(date: date(2026, 8, 8), duration: 64 * 60),
            ReadingDaySummary(date: date(2026, 8, 11), duration: 35 * 60),
            ReadingDaySummary(date: date(2026, 8, 14), duration: 51 * 60),
            ReadingDaySummary(date: date(2026, 8, 18), duration: 29 * 60),
            ReadingDaySummary(date: date(2026, 8, 21), duration: 73 * 60),
            ReadingDaySummary(date: date(2026, 8, 26), duration: 46 * 60),
            ReadingDaySummary(date: date(2026, 8, 30), duration: 38 * 60)
        ],
        inProgressBooks: [
            StatisticsBookSummary(
                id: UUID(uuidString: "82A849AE-8F00-42D1-B7B8-7A26ED9B7822")!,
                title: "L’Usage du monde",
                author: "Nicolas Bouvier",
                coverData: nil,
                progress: 0.42,
                startedAt: date(2026, 7, 19),
                finishedAt: nil,
                rating: nil
            ),
            StatisticsBookSummary(
                id: UUID(uuidString: "6F6608AA-525B-482A-9D41-7876DF1A5316")!,
                title: "La Montagne magique",
                author: "Thomas Mann",
                coverData: nil,
                progress: 0.18,
                startedAt: date(2026, 8, 7),
                finishedAt: nil,
                rating: nil
            )
        ],
        finishedBooks: [
            StatisticsBookSummary(
                id: UUID(uuidString: "B24C54C6-2E0B-4A14-BD26-D80A168541C7")!,
                title: "Le Guépard",
                author: "Giuseppe Tomasi di Lampedusa",
                coverData: nil,
                progress: 1,
                startedAt: date(2026, 8, 3),
                finishedAt: date(2026, 8, 24),
                rating: 9
            )
        ]
    )

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
