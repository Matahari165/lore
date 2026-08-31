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

struct LoreAICharactersConceptsContext: Equatable, Sendable {
    let title: String
    let author: String?
    let chapterTitles: [String]
    let readText: String

    init(title: String, author: String? = nil, chapterTitles: [String] = [], readText: String) {
        self.title = title
        self.author = author
        self.chapterTitles = chapterTitles
        self.readText = readText
    }
}

struct LoreAIFlashcardsContext: Equatable, Sendable {
    let title: String
    let author: String?
    let chapterTitles: [String]
    let readText: String
    let cardCount: Int

    init(title: String, author: String? = nil, chapterTitles: [String] = [], readText: String, cardCount: Int) {
        self.title = title
        self.author = author
        self.chapterTitles = chapterTitles
        self.readText = readText
        self.cardCount = cardCount
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

protocol LoreAIAdvancedService: Sendable {
    func summarizeChapter(_ context: LoreAIChapterContext) async throws -> String
    func answerQuestion(_ context: LoreAIQuestionContext) async throws -> String
    func identifyCharactersAndConcepts(_ context: LoreAICharactersConceptsContext) async throws -> String
    func generateFlashcards(_ context: LoreAIFlashcardsContext) async throws -> String
    func discussEnding(_ context: LoreAIEndingDiscussionContext) async throws -> String
}
