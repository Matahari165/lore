import Foundation

enum LoreAIFeature: Sendable {
    case explainSelection
    case previousReadingRecap
}

struct BookAIContext: Equatable, Sendable {
    let title: String
    let author: String?
    let chapterTitle: String?
    let textBefore: String
    let selectedText: String
    let textAfter: String

    init(
        title: String,
        author: String? = nil,
        chapterTitle: String? = nil,
        textBefore: String,
        selectedText: String,
        textAfter: String
    ) {
        self.title = title
        self.author = author
        self.chapterTitle = chapterTitle
        self.textBefore = textBefore
        self.selectedText = selectedText
        self.textAfter = textAfter
    }
}

struct PreviousReadingContext: Equatable, Sendable {
    let title: String
    let author: String?
    let chapterTitles: [String]
    let excerpt: String
    let lastReadPositionDescription: String?

    init(
        title: String,
        author: String? = nil,
        chapterTitles: [String] = [],
        excerpt: String,
        lastReadPositionDescription: String? = nil
    ) {
        self.title = title
        self.author = author
        self.chapterTitles = chapterTitles
        self.excerpt = excerpt
        self.lastReadPositionDescription = lastReadPositionDescription
    }
}

struct LoreAIPrompt: Equatable, Sendable {
    let developer: String
    let user: String
}

protocol LoreAIService: Sendable {
    func explain(_ context: BookAIContext) async throws -> String
    func recap(_ context: PreviousReadingContext) async throws -> String
}

enum LoreAIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)
    case transport(String)
    case emptyContext

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Ajoute une clé API OpenAI dans les réglages pour utiliser l’intelligence artificielle."
        case .invalidAPIKey:
            "La clé API enregistrée n’est pas valide."
        case .invalidResponse:
            "La réponse de l’intelligence artificielle est illisible. Réessaie."
        case let .requestFailed(statusCode, message):
            message.map { "Erreur du service IA (\(statusCode)) : \($0)" }
                ?? "Le service IA a répondu avec l’erreur \(statusCode)."
        case let .transport(message):
            "Connexion au service IA impossible : \(message)"
        case .emptyContext:
            "Aucun texte exploitable n’est disponible pour cette demande."
        }
    }
}
