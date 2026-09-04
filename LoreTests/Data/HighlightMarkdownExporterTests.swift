import Foundation
import ReadiumShared
import Testing
@testable import Lore

struct HighlightMarkdownExporterTests {
    @Test func exportsMultipleBooksDeterministicallyAndEscapesMultilineContent() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let locator = Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml)
        let first = ReaderHighlight(
            id: firstID, bookID: secondID, locator: locator, text: "Ligne *une*\n> citation\n- liste\n1. numéro",
            createdAt: date, color: .yellow, note: "Note [liée]\n+ ajout\navec `code`"
        )
        let second = ReaderHighlight(
            id: secondID, bookID: firstID, locator: locator, text: "Autre",
            createdAt: date, color: .yellow, note: nil
        )
        let groups = [
            BookHighlightGroup(bookID: secondID, title: "Zèbre", author: nil, highlights: [first]),
            BookHighlightGroup(bookID: firstID, title: "Alpha", author: "A_uteur", highlights: [second])
        ]

        let markdown = HighlightMarkdownExporter.export(groups: groups)
        #expect(markdown == HighlightMarkdownExporter.export(groups: Array(groups.reversed())))
        #expect(markdown.range(of: "## Alpha")!.lowerBound < markdown.range(of: "## Zèbre")!.lowerBound)
        #expect(markdown.contains("> Ligne \\*une\\*\n> \\> citation\n> \\- liste\n> 1\\. numéro"))
        #expect(markdown.contains("> Note \\[liée\\]\n> \\+ ajout\n> avec \\`code\\`"))
        #expect(!markdown.contains("chapter.xhtml"))
    }

    @Test func exportsReadableEmptyDocument() {
        #expect(HighlightMarkdownExporter.export(groups: []) == "# Annotations Lore\n")
    }

    @Test func exportsEmptyPassageAndNoteAsExplicitBlockquoteLines() {
        let bookID = UUID()
        let highlight = ReaderHighlight(
            id: UUID(), bookID: bookID,
            locator: Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml),
            text: "", createdAt: .now, color: .yellow, note: ""
        )
        let markdown = HighlightMarkdownExporter.export(groups: [
            BookHighlightGroup(bookID: bookID, title: "Livre", author: nil, highlights: [highlight])
        ])

        #expect(markdown.contains("\n> \n\n**Note personnelle**\n\n> \n"))
    }

    @Test func searchIgnoresCaseAndDiacriticsAcrossBookPassageAndNote() {
        let bookID = UUID()
        let highlight = ReaderHighlight(
            id: UUID(),
            bookID: bookID,
            locator: Locator(href: URL(string: "chapter.xhtml")!, mediaType: .xhtml),
            text: "Une pensée claire",
            createdAt: .now,
            color: .yellow,
            note: "À réutiliser bientôt"
        )
        let group = BookHighlightGroup(bookID: bookID, title: "L’Étranger", author: "Albert Camus", highlights: [highlight])

        #expect(HighlightSearchMatcher.matches("etranger", group: group, highlight: highlight))
        #expect(HighlightSearchMatcher.matches("PENSÉE", group: group, highlight: highlight))
        #expect(HighlightSearchMatcher.matches("reutiliser", group: group, highlight: highlight))
        #expect(!HighlightSearchMatcher.matches("absent", group: group, highlight: highlight))
    }
}
