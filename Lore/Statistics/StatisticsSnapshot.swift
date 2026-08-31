import Foundation

struct StatisticsSnapshot: Sendable, Equatable {
    /// Premier instant du mois civil demandé, dans le fuseau du calendrier fourni.
    let referenceMonth: Date
    /// Durées actives exactes en secondes. L’arrondi appartient uniquement à la vue.
    let todayDuration: TimeInterval
    let weekDuration: TimeInterval
    let monthDuration: TimeInterval
    let readingDays: [ReadingDaySummary]
    let inProgressBooks: [StatisticsBookSummary]
    let finishedBooks: [StatisticsBookSummary]
}

struct ReadingDaySummary: Identifiable, Sendable, Equatable {
    let date: Date
    let duration: TimeInterval

    var id: Date { date }
}

/// A single local-calendar bucket used by the reading activity chart.
/// Duration stays in seconds so the view can choose the appropriate display unit.
struct ReadingActivityPoint: Identifiable, Sendable, Equatable {
    let date: Date
    let duration: TimeInterval

    var id: Date { date }
}

enum ReadingActivityChartRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month

    var id: Self { self }

    var title: String {
        switch self {
        case .week: "Semaine"
        case .month: "Mois"
        }
    }
}

struct StatisticsBookSummary: Identifiable, Sendable, Equatable {
    let id: UUID
    let title: String
    let author: String?
    let coverData: Data?
    let progress: Double?
    /// Date de la première session réelle, calculée depuis les sessions persistées.
    let startedAt: Date?
    let finishedAt: Date?
    /// Année choisie par l’utilisateur lors de la validation de la lecture.
    let readingYear: Int?
    /// Note entière comprise entre 0 et 10.
    let rating: Int?
}

enum StatisticsScreenState: Sendable, Equatable {
    case loading
    case loaded(StatisticsSnapshot)
    case empty
    case failed(message: String)
}
