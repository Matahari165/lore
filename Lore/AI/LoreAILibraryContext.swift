import Foundation

/// Résumé local d'un livre pour l'IA globale de bibliothèque.
///
/// Ne contient que des métadonnées déjà persistées par Lore et les notes
/// personnelles de l'utilisateur. Aucun texte EPUB complet n'y figure :
/// seuls de courts extraits surlignés (déjà annotés par l'utilisateur)
/// peuvent accompagner une note.
struct LoreAILibraryBookSummary: Equatable, Sendable {
    let title: String
    let author: String?
    /// "terminé", "en cours" ou "à lire".
    let status: String
    let progression: Double?
    let rating: Int?
    let readingYear: Int?
    let importedAt: Date?
    let finishedAt: Date?
    let firstReadAt: Date?
    let lastReadAt: Date?
    /// Minutes de lecture active cumulées, arrondies pour l'affichage.
    let totalReadingMinutes: Int?
    let collections: [String]
    let highlightCount: Int
    let noteCount: Int
    let notes: [LoreAILibraryNote]
}

struct LoreAILibraryNote: Equatable, Sendable {
    /// Court passage surligné par l'utilisateur (borné par le builder).
    let passage: String?
    /// Note personnelle attachée au surlignage (bornée par le builder).
    let note: String?
    let createdAt: Date?
}

struct LoreAILibraryContext: Equatable, Sendable {
    let books: [LoreAILibraryBookSummary]
    let question: String
    let history: [LoreAIChatMessage]

    init(books: [LoreAILibraryBookSummary], question: String, history: [LoreAIChatMessage] = []) {
        self.books = books
        self.question = question
        self.history = history
    }

    var finishedCount: Int { books.filter { $0.status == "terminé" }.count }
    var inProgressCount: Int { books.filter { $0.status == "en cours" }.count }
}
