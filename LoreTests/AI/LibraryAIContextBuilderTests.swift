import Foundation
import Testing
@testable import Lore

struct LibraryAIContextBuilderTests {
    private func input(
        title: String = "Livre",
        status: String = "terminé",
        rating: Int? = 8,
        note: String? = "Note personnelle"
    ) -> LibraryAIBookInput {
        LibraryAIBookInput(
            title: title,
            author: "Auteur",
            status: status,
            progression: 1.0,
            rating: rating,
            readingYear: 2026,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_710_000_000),
            firstReadAt: Date(timeIntervalSince1970: 1_705_000_000),
            lastReadAt: Date(timeIntervalSince1970: 1_709_000_000),
            totalReadingMinutes: 320,
            collections: ["Favoris"],
            highlights: [.init(text: "Passage marquant", note: note, createdAt: Date(timeIntervalSince1970: 1_706_000_000))]
        )
    }

    @Test func finishedBooksComeFirstAndNotesAreKept() throws {
        let context = try LibraryAIContextBuilder.build(
            inputs: [
                input(title: "À lire", status: "à lire", rating: nil, note: nil),
                input(title: "Terminé"),
            ],
            question: "Recommande-moi un livre"
        )
        #expect(context.books.first?.title == "Terminé")
        #expect(context.books.first?.rating == 8)
        #expect(context.books.first?.notes.first?.note == "Note personnelle")
        #expect(context.finishedCount == 1)
    }

    @Test func emptyQuestionOrEmptyLibraryThrows() {
        #expect(throws: LoreAIError.emptyContext) {
            try LibraryAIContextBuilder.build(inputs: [input()], question: "   ")
        }
        #expect(throws: LoreAIError.emptyContext) {
            try LibraryAIContextBuilder.build(inputs: [], question: "Recommande")
        }
    }

    @Test func libraryPromptStaysLocalAndStructured() throws {
        let context = try LibraryAIContextBuilder.build(
            inputs: [input()],
            question: "Que me conseilles-tu ?"
        )
        let prompt = try LoreAILibraryPromptBuilder().prompt(for: context)
        #expect(prompt.developer.contains("bibliothèque personnelle"))
        #expect(prompt.developer.contains("Maximum 6 puces"))
        #expect(prompt.user.contains("Terminé") || prompt.user.contains("Livre"))
        #expect(prompt.user.contains("Que me conseilles-tu"))
    }
}
