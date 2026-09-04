import Foundation

/// Contexte d'un chapitre déjà fourni par l'extracteur local.
struct LoreAIChapterContext: Equatable, Sendable {
    let title: String
    let author: String?
    let chapterTitle: String?
    let chapterText: String

    init(title: String, author: String? = nil, chapterTitle: String? = nil, chapterText: String) {
        self.title = title
        self.author = author
        self.chapterTitle = chapterTitle
        self.chapterText = chapterText
    }
}

/// Question limitée au contenu effectivement lu et transmis par l'app.
struct LoreAIQuestionContext: Equatable, Sendable {
    let title: String
    let author: String?
    let chapterTitle: String?
    let readText: String
    let question: String
    let lastReadPositionDescription: String?

    init(
        title: String,
        author: String? = nil,
        chapterTitle: String? = nil,
        readText: String,
        question: String,
        lastReadPositionDescription: String? = nil
    ) {
        self.title = title
        self.author = author
        self.chapterTitle = chapterTitle
        self.readText = readText
        self.question = question
        self.lastReadPositionDescription = lastReadPositionDescription
    }
}

struct LoreAIEndingDiscussionContext: Equatable, Sendable {
    let title: String
    let author: String?
    let chapterTitle: String?
    let readText: String
    let lastReadPositionDescription: String?

    init(
        title: String,
        author: String? = nil,
        chapterTitle: String? = nil,
        readText: String,
        lastReadPositionDescription: String? = nil
    ) {
        self.title = title
        self.author = author
        self.chapterTitle = chapterTitle
        self.readText = readText
        self.lastReadPositionDescription = lastReadPositionDescription
    }
}

/// Amorce locale affichée après la fin d'un livre. Elle ne contient aucun
/// extrait EPUB : le lecteur choisit ensuite ce que le client IA peut envoyer.
enum LoreAIEndingDiscussionGuide {
    static let kickoffPrompt = """
    Je viens de terminer ce livre. Guide-moi pas à pas pour en tirer quelque chose de durable :
    1. les idées essentielles ou, pour une fiction, les thèmes et choix marquants ;
    2. ce que cette lecture change dans ma compréhension ;
    3. des applications concrètes ou, pour une fiction, ce que je veux retenir de l'expérience ;
    4. des questions de rappel actif, une seule à la fois, en attendant ma réponse avant de continuer.

    Commence par indiquer clairement quels extraits tu as réellement reçus. Ne prétends jamais connaître le livre complet si le contexte intégral n'a pas été autorisé et transmis.
    """
}

protocol LoreAIAdvancedService: Sendable {
    func summarizeChapter(_ context: LoreAIChapterContext) async throws -> String
    func answerQuestion(_ context: LoreAIQuestionContext) async throws -> String
    func discussEnding(_ context: LoreAIEndingDiscussionContext) async throws -> String
}
