import Foundation

/// Entrée valeur préparée sur le MainActor depuis SwiftData, afin que
/// l'assemblage du contexte reste testable et sans accès base.
struct LibraryAIBookInput: Sendable {
    let title: String
    let author: String?
    let status: String
    let progression: Double?
    let rating: Int?
    let readingYear: Int?
    let importedAt: Date?
    let finishedAt: Date?
    let firstReadAt: Date?
    let lastReadAt: Date?
    let totalReadingMinutes: Int?
    let collections: [String]
    let highlights: [LibraryAIHighlightInput]
}

struct LibraryAIHighlightInput: Sendable {
    let text: String
    let note: String?
    let createdAt: Date?
}

/// Assemble un contexte bibliothèque borné et pertinent pour les recommandations.
///
/// Politique : métadonnées d'abord (titre, auteur, statut, note, dates, temps
/// de lecture), puis un petit nombre de notes personnelles par livre. Le texte
/// complet des EPUB n'est jamais inclus. Tout est tronqué localement avant envoi.
enum LibraryAIContextBuilder {
    struct Limits: Equatable, Sendable {
        var maxBooks = 80
        var perBookCharacters = 1_200
        var notesPerBook = 5
        var passageCharacters = 300
        var noteCharacters = 300
        /// Budget total du contexte : livres + question + historique.
        var totalCharacters = 30_000
        var questionCharacters = 1_000
        var historyCharacters = 6_000
        var historyMessages = 12

        static let production = Limits()
    }

    static func build(
        inputs: [LibraryAIBookInput],
        question: String,
        history: [LoreAIChatMessage] = [],
        limits: Limits = .production
    ) throws -> LoreAILibraryContext {
        let cleanedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuestion.isEmpty else { throw LoreAIError.emptyContext }
        guard limits.maxBooks > 0, limits.totalCharacters > 0 else {
            throw LoreAIError.invalidChatContext
        }
        let boundedQuestion = cleanedQuestion.count <= limits.questionCharacters
            ? cleanedQuestion
            : String(cleanedQuestion.prefix(limits.questionCharacters)) + "\n[…question limitée…]"
        let bounded = boundedHistory(history, limits: limits)

        // Le budget total couvre livres + question + historique : les livres
        // se partagent ce qui reste après la question et l'historique.
        let historyCost = bounded.reduce(0) { $0 + $1.text.count }

        // Livres terminés et en cours d'abord : les plus pertinents pour une reco.
        let ranked = inputs.sorted { lhs, rhs in
            rank(lhs.status) < rank(rhs.status)
        }
        var books: [LoreAILibraryBookSummary] = []
        var remaining = max(0, limits.totalCharacters - boundedQuestion.count - historyCost)
        for input in ranked.prefix(limits.maxBooks) {
            guard remaining > 0 else { break }
            let summary = summarize(input, limits: limits, budget: &remaining)
            books.append(summary)
        }
        guard !books.isEmpty else { throw LoreAIError.emptyContext }
        return LoreAILibraryContext(
            books: books,
            question: boundedQuestion,
            history: bounded
        )
    }

    private static func rank(_ status: String) -> Int {
        switch status {
        case "terminé": 0
        case "en cours": 1
        default: 2
        }
    }

    private static func summarize(
        _ input: LibraryAIBookInput,
        limits: Limits,
        budget: inout Int
    ) -> LoreAILibraryBookSummary {
        // Les notes sont les signaux les plus personnels : on les garde en
        // priorité, les plus récentes d'abord.
        let sorted = input.highlights.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
        var notes: [LoreAILibraryNote] = []
        var notesBudget = min(limits.perBookCharacters / 2, budget / 2)
        for highlight in sorted.prefix(limits.notesPerBook) {
            let passage: String? = clip(highlight.text, maximum: limits.passageCharacters)
            let note: String? = highlight.note.flatMap { clip($0, maximum: limits.noteCharacters) }
            guard !(passage?.isEmpty ?? true) || !(note?.isEmpty ?? true) else { continue }
            let cost = (passage?.count ?? 0) + (note?.count ?? 0)
            guard cost <= notesBudget else { continue }
            notesBudget -= cost
            notes.append(LoreAILibraryNote(
                passage: passage?.isEmpty == true ? nil : passage,
                note: note?.isEmpty == true ? nil : note,
                createdAt: highlight.createdAt
            ))
        }
        let highlightCount = input.highlights.count
        let noteCount = input.highlights.filter {
            !($0.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }.count
        let summary = LoreAILibraryBookSummary(
            title: clip(input.title, maximum: 200) ?? "Livre sans titre",
            author: clip(input.author ?? "", maximum: 120)?.nilIfEmpty,
            status: input.status,
            progression: input.progression,
            rating: input.rating,
            readingYear: input.readingYear,
            importedAt: input.importedAt,
            finishedAt: input.finishedAt,
            firstReadAt: input.firstReadAt,
            lastReadAt: input.lastReadAt,
            totalReadingMinutes: input.totalReadingMinutes,
            collections: Array(input.collections.prefix(6)),
            highlightCount: highlightCount,
            noteCount: noteCount,
            notes: notes
        )
        // Décompte approximatif : borne le total envoyé, pas au caractère près.
        let estimate = estimateCharacters(of: summary)
        budget = max(0, budget - min(estimate, limits.perBookCharacters))
        return summary
    }

    private static func estimateCharacters(of summary: LoreAILibraryBookSummary) -> Int {
        var count = summary.title.count + (summary.author?.count ?? 0) + summary.status.count + 120
        count += summary.collections.joined(separator: ",").count
        for note in summary.notes {
            count += (note.passage?.count ?? 0) + (note.note?.count ?? 0)
        }
        return count
    }

    private static func boundedHistory(
        _ source: [LoreAIChatMessage],
        limits: Limits
    ) -> [LoreAIChatMessage] {
        let candidates = source.suffix(limits.historyMessages)
        var remaining = limits.historyCharacters
        var selected: [LoreAIChatMessage] = []
        for message in candidates.reversed() {
            guard remaining > 0 else { break }
            let cleaned = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let clipped = String(cleaned.prefix(remaining))
            selected.append(LoreAIChatMessage(role: message.role, text: clipped))
            remaining -= clipped.count
        }
        return selected.reversed()
    }

    private static func clip(_ value: String, maximum: Int) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count > maximum else { return cleaned }
        return String(cleaned.prefix(maximum))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
