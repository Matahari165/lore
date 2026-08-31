import Foundation
import ReadiumShared
import SwiftData
import Testing
@testable import Lore

@MainActor
struct VocabularyRepositoryTests {
    @Test func storesListsAndDeletesVocabularyByBook() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: VocabularyRecord.self, configurations: configuration)
        let repository = VocabularyRepository(context: container.mainContext)
        let firstBookID = UUID()
        let secondBookID = UUID()
        let locator = Locator(
            href: URL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            text: .init(highlight: "deliberate practice")
        )

        let saved = try repository.addVocabulary(
            bookID: firstBookID,
            locator: locator,
            text: "  deliberate practice  "
        )
        _ = try repository.addVocabulary(bookID: secondBookID, locator: locator, text: "focus")

        #expect(saved.text == "deliberate practice")
        #expect(try repository.vocabulary(for: firstBookID).map(\.text) == ["deliberate practice"])
        #expect(try repository.allVocabulary().count == 2)

        try repository.deleteVocabulary(id: saved.id, bookID: firstBookID)
        #expect(try repository.vocabulary(for: firstBookID).isEmpty)
        #expect(try repository.vocabulary(for: secondBookID).count == 1)
    }

    @Test func emptySelectionIsRejectedWithoutCreatingARecord() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: VocabularyRecord.self, configurations: configuration)
        let repository = VocabularyRepository(context: container.mainContext)
        let locator = Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml)

        #expect(throws: VocabularyStoreError.emptyText) {
            try repository.addVocabulary(bookID: UUID(), locator: locator, text: "   \n")
        }
        #expect(try repository.allVocabulary().isEmpty)
    }
}
