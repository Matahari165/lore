import Foundation
import ReadiumShared
import SwiftData
import Testing
@testable import Lore

@MainActor
struct AIConversationRepositoryTests {
    @Test func persistsAnswerAndValidatedSourcesTogether() throws {
        let fixture = try Fixture()
        let bookID = UUID()
        let source = try makeSource(bookID: bookID, progression: 0.4)

        try fixture.repository.appendTurn(
            bookID: bookID,
            question: "Que se passe-t-il ?",
            answer: "Voici le passage utilisé.",
            sources: [source],
            frontierProgression: 0.5
        )

        let history = try fixture.repository.history(for: bookID)
        #expect(history.count == 2)
        #expect(history.last?.sources == [source])
    }

    @Test func readsLegacyMessagesWithoutSources() throws {
        let fixture = try Fixture()
        let bookID = UUID()
        let conversation = AIConversationRecord(bookID: bookID)
        fixture.container.mainContext.insert(conversation)
        fixture.container.mainContext.insert(AIMessageRecord(
            conversationID: conversation.id,
            role: .assistant,
            text: "Ancienne réponse",
            sequence: 0
        ))
        try fixture.container.mainContext.save()

        let message = try #require(fixture.repository.history(for: bookID).first)
        #expect(message.text == "Ancienne réponse")
        #expect(message.sources.isEmpty)
    }

    @Test func hidesCorruptedCurrentSchemaSourcesFromHistory() throws {
        let fixture = try Fixture()
        let bookID = UUID()
        let conversation = AIConversationRecord(bookID: bookID)
        let invalid = LoreAIChatSource(
            id: "source", bookID: UUID(), label: "Étrangère",
            locatorJSON: Data("invalid".utf8), locatorSchemaVersion: 1, progression: 0.2
        )
        fixture.container.mainContext.insert(conversation)
        fixture.container.mainContext.insert(AIMessageRecord(
            conversationID: conversation.id, role: .assistant, text: "Réponse", sequence: 0,
            frontierProgression: 0.5,
            sourcesJSON: try JSONEncoder().encode([invalid]), sourcesSchemaVersion: 1,
            readingStage: .inProgress
        ))
        try fixture.container.mainContext.save()
        #expect(try fixture.repository.history(for: bookID).first?.sources.isEmpty == true)
    }

    @Test func rejectsInvalidSourceBeforePersistence() throws {
        let fixture = try Fixture()
        let bookID = UUID()
        let invalid = try makeSource(bookID: bookID, id: "   ", progression: 0.4)

        #expect(throws: AIConversationRepositoryError.invalidSource) {
            try fixture.repository.appendTurn(
                bookID: bookID,
                question: "Question",
                answer: "Réponse",
                sources: [invalid],
                frontierProgression: 0.5
            )
        }
        #expect(try fixture.repository.history(for: bookID).isEmpty)
    }

    @Test(arguments: [-0.01, 1.01])
    func rejectsOutOfRangeProgressionBeforePersistence(_ progression: Double) throws {
        let fixture = try Fixture()
        let bookID = UUID()
        let invalid = try makeSource(bookID: bookID, progression: progression)
        #expect(throws: AIConversationRepositoryError.invalidSource) {
            try fixture.repository.appendTurn(
                bookID: bookID, question: "Question", answer: "Réponse",
                sources: [invalid], frontierProgression: 1
            )
        }
        #expect(try fixture.repository.history(for: bookID).isEmpty)
    }

    @Test func finishedTurnAcceptsValidatedSourceWithoutFrontier() throws {
        let fixture = try Fixture()
        let bookID = UUID()
        let source = try makeSource(bookID: bookID, progression: 1)
        try fixture.repository.appendTurn(
            bookID: bookID,
            question: "La fin ?",
            answer: "Réponse",
            sources: [source],
            readingStage: .finished,
            frontierProgression: nil,
            fullBookAccessGranted: true
        )
        #expect(try fixture.repository.history(for: bookID).last?.sources == [source])
    }

    @Test func createsIndependentConversationsAndReopensTheMostRecent() throws {
        let fixture = try Fixture()
        let bookID = UUID()
        let first = try fixture.repository.appendTurn(
            bookID: bookID,
            question: "Première question",
            answer: "Première réponse",
            at: Date(timeIntervalSince1970: 1)
        )
        let second = try fixture.repository.appendTurn(
            bookID: bookID,
            question: "Nouvelle question",
            answer: "Nouvelle réponse",
            at: Date(timeIntervalSince1970: 2)
        )

        #expect(first.id != second.id)
        #expect(try fixture.repository.conversations(for: bookID).map(\.id) == [second.id, first.id])
        #expect(try fixture.repository.history(for: bookID).last?.text == "Nouvelle réponse")
        #expect(try fixture.repository.history(for: bookID, conversationID: first.id).last?.text == "Première réponse")
    }

    @Test func hidesTurnsWrittenAfterTheCurrentReadingFrontier() throws {
        let fixture = try Fixture()
        let bookID = UUID()
        let conversation = try fixture.repository.appendTurn(
            bookID: bookID,
            question: "Question déjà lue",
            answer: "Réponse déjà lue",
            readingStage: .inProgress,
            frontierProgression: 0.4,
            at: Date(timeIntervalSince1970: 1)
        )
        try fixture.repository.appendTurn(
            bookID: bookID,
            conversationID: conversation.id,
            question: "Question future",
            answer: "Réponse future",
            readingStage: .inProgress,
            frontierProgression: 0.8,
            at: Date(timeIntervalSince1970: 2)
        )

        let beforeFuture = try fixture.repository.history(
            for: bookID,
            conversationID: conversation.id,
            maximumFrontierProgression: 0.5,
            readingStage: .inProgress
        )
        let afterFuture = try fixture.repository.history(
            for: bookID,
            conversationID: conversation.id,
            maximumFrontierProgression: 0.9,
            readingStage: .inProgress
        )
        #expect(beforeFuture.map(\.text) == ["Question déjà lue", "Réponse déjà lue"])
        #expect(afterFuture.count == 4)
    }

    @Test func invalidSourceSchemaIsRejected() throws {
        let fixture = try Fixture()
        let bookID = UUID()
        let valid = try makeSource(bookID: bookID, progression: 0.4)
        let invalid = LoreAIChatSource(
            id: valid.id, bookID: bookID, label: valid.label,
            locatorJSON: valid.locatorJSON, locatorSchemaVersion: 99, progression: 0.4
        )
        #expect(throws: AIConversationRepositoryError.invalidSource) {
            try fixture.repository.appendTurn(
                bookID: bookID, question: "Question", answer: "Réponse",
                sources: [invalid], frontierProgression: 0.5
            )
        }
    }

    @Test func failedSaveLeavesNoHalfPersistedTurn() throws {
        enum SaveFailure: Error { case expected }
        let fixture = try Fixture(save: { _ in throw SaveFailure.expected })
        let bookID = UUID()
        #expect(throws: SaveFailure.expected) {
            try fixture.repository.appendTurn(
                bookID: bookID, question: "Question", answer: "Réponse"
            )
        }
        #expect(try fixture.repository.conversation(for: bookID) == nil)
    }

    private func makeSource(
        bookID: UUID,
        id: String = "source-local-1",
        progression: Double
    ) throws -> LoreAIChatSource {
        let locator = Locator(
            href: URL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(totalProgression: progression),
            text: .init(highlight: "passage exact")
        )
        let stored = try LocatorPersistenceCodec.encode(locator)
        return LoreAIChatSource(
            id: id,
            bookID: bookID,
            label: "Passage 1",
            locatorJSON: stored.data,
            locatorSchemaVersion: try #require(stored.schemaVersion),
            progression: progression
        )
    }
}

@MainActor
private final class Fixture {
    let container: ModelContainer
    let repository: AIConversationRepository

    init(save: ((ModelContext) throws -> Void)? = nil) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: AIConversationRecord.self,
            AIMessageRecord.self,
            configurations: configuration
        )
        repository = AIConversationRepository(context: container.mainContext, save: save)
    }
}
