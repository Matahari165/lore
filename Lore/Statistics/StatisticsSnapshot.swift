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

struct StatisticsBookSummary: Identifiable, Sendable, Equatable {
    let id: UUID
    let title: String
    let author: String?
    let coverData: Data?
    let progress: Double?
    /// Date de la première session réelle, calculée depuis les sessions persistées.
    let startedAt: Date?
    let finishedAt: Date?
    /// Note entière comprise entre 0 et 10.
    let rating: Int?
}

enum StatisticsScreenState: Sendable, Equatable {
    case loading
    case loaded(StatisticsSnapshot)
    case empty
    case failed(message: String)
}
