import Foundation

enum LoreAIFeature: Sendable {
    case explainSelection
    case previousReadingRecap
    case chapterSummary
    case bookQuestion
    case endingDiscussion
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
    /// Turns are sent as separate Responses API messages so the model can
    /// follow the conversation without relying on remote stored state.
    let history: [LoreAIChatMessage]

    init(developer: String, user: String, history: [LoreAIChatMessage] = []) {
        self.developer = developer
        self.user = user
        self.history = history
    }
}

/// Etape de lecture visible par l'assistant. Elle contrôle le périmètre des
/// extraits : avant lecture, aucun texte ; en cours, seulement la frontière
/// déjà lue ; après la fin, les extraits du livre entier sont possibles après
/// consentement explicite.
enum LoreAIReadingStage: String, Codable, Equatable, Sendable {
    case notStarted
    case inProgress
    case finished
}

enum LoreAIChatRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

struct LoreAIChatMessage: Equatable, Codable, Sendable {
    let role: LoreAIChatRole
    let text: String

    init(role: LoreAIChatRole, text: String) {
        self.role = role
        self.text = text
    }
}

/// Un fragment sélectionné localement. Pour une analyse de fin, l'appelant
/// doit fournir plusieurs fragments bornés et non l'EPUB comme un seul bloc.
struct LoreAIChatExcerpt: Equatable, Sendable {
    let text: String
    let sourceDescription: String?
    let progression: Double?

    init(text: String, sourceDescription: String? = nil, progression: Double? = nil) {
        self.text = text
        self.sourceDescription = sourceDescription
        self.progression = progression
    }
}

struct LoreAIChatContext: Equatable, Sendable {
    let bookID: UUID?
    let title: String
    let author: String?
    let stage: LoreAIReadingStage
    let chapterTitle: String?
    let readFrontierProgression: Double?
    let readFrontierDescription: String?
    let excerpts: [LoreAIChatExcerpt]
    let fullBookAccessGranted: Bool
    let history: [LoreAIChatMessage]
    let question: String

    init(
        bookID: UUID? = nil,
        title: String,
        author: String? = nil,
        stage: LoreAIReadingStage,
        chapterTitle: String? = nil,
        readFrontierProgression: Double? = nil,
        readFrontierDescription: String? = nil,
        excerpts: [LoreAIChatExcerpt] = [],
        fullBookAccessGranted: Bool = false,
        history: [LoreAIChatMessage] = [],
        question: String
    ) {
        self.bookID = bookID
        self.title = title
        self.author = author
        self.stage = stage
        self.chapterTitle = chapterTitle
        self.readFrontierProgression = readFrontierProgression
        self.readFrontierDescription = readFrontierDescription
        self.excerpts = excerpts
        self.fullBookAccessGranted = fullBookAccessGranted
        self.history = history
        self.question = question
    }
}

protocol LoreAIChatService: Sendable {
    func chat(_ context: LoreAIChatContext) async throws -> String
}

protocol LoreAIService: LoreAIChatService {
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
    case invalidChatContext
    case futureReadingContext

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
        case .invalidChatContext:
            "Le contexte de lecture fourni n’est pas valide."
        case .futureReadingContext:
            "Ce passage dépasse votre progression de lecture actuelle."
        }
    }
}
