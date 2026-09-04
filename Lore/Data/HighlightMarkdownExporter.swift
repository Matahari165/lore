import Foundation

struct BookHighlightGroup: Identifiable, Sendable {
    let bookID: UUID
    let title: String
    let author: String?
    var highlights: [ReaderHighlight]
    var id: UUID { bookID }
}

enum HighlightSearchMatcher {
    static func matches(_ query: String, group: BookHighlightGroup, highlight: ReaderHighlight) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty
            || group.title.localizedStandardContains(normalized)
            || (group.author?.localizedStandardContains(normalized) ?? false)
            || highlight.text.localizedStandardContains(normalized)
            || (highlight.note?.localizedStandardContains(normalized) ?? false)
    }
}

enum HighlightMarkdownExporter {
    static func export(groups: [BookHighlightGroup]) -> String {
        let sortedGroups = groups.sorted {
            let comparison = $0.title.localizedStandardCompare($1.title)
            return comparison == .orderedSame ? $0.bookID.uuidString < $1.bookID.uuidString : comparison == .orderedAscending
        }
        var lines = ["# Annotations Lore"]
        for group in sortedGroups {
            lines.append(contentsOf: ["", "## \(escaped(group.title))"])
            if let author = group.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                lines.append(contentsOf: ["", "_\(escaped(author))_"])
            }
            for highlight in group.highlights.sorted(by: stableHighlightOrder) {
                lines.append(contentsOf: ["", "### \(highlight.createdAt.formatted(.iso8601.year().month().day()))", ""])
                lines.append(contentsOf: blockquote(highlight.text))
                if let note = highlight.note {
                    lines.append(contentsOf: ["", "**Note personnelle**", ""])
                    lines.append(contentsOf: blockquote(note))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func stableHighlightOrder(_ lhs: ReaderHighlight, _ rhs: ReaderHighlight) -> Bool {
        lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt < rhs.createdAt
    }

    private static func blockquote(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \(escaped(String($0)))" }
    }

    private static func escaped(_ text: String) -> String {
        let markdownPunctuation = CharacterSet(charactersIn: "\\`*_{}[]<>()#+-.!|>")
        return text.unicodeScalars.reduce(into: "") { result, scalar in
            if markdownPunctuation.contains(scalar) { result.append("\\") }
            result.unicodeScalars.append(scalar)
        }
    }
}
