import Foundation

struct StatisticsSnapshot: Sendable {
    /// Mois civil dans le fuseau local de l’iPhone.
    let referenceMonth: Date
    /// Durées actives exactes en secondes. L’arrondi appartient uniquement à la vue.
    let todayDuration: TimeInterval
    let weekDuration: TimeInterval
    let monthDuration: TimeInterval
    let readingDays: [ReadingDaySummary]
    let inProgressBooks: [StatisticsBookSummary]
    let finishedBooks: [StatisticsBookSummary]
}

struct ReadingDaySummary: Identifiable, Sendable {
    let date: Date
    let duration: TimeInterval

    var id: Date { date }
}

struct StatisticsBookSummary: Identifiable, Sendable {
    let id: UUID
    let title: String
    let author: String?
    let coverData: Data?
    let progress: Double?
    /// Date de la première session réelle, déjà calculée par la couche Données.
    let startedAt: Date?
    let finishedAt: Date?
    /// Note entière comprise entre 0 et 10, fournie par la couche Données.
    let rating: Int?
}

enum StatisticsScreenState: Sendable {
    case loading
    case loaded(StatisticsSnapshot)
    case empty
    case failed(message: String)
}
