import Foundation
import NaturalLanguage
import ReadiumShared

/// Représente une phrase extraite d'un chapitre EPUB prête pour la synthèse vocale locale.
struct LoreTTSSentence: Equatable, Sendable {
    let chapterIndex: Int
    let sentenceIndex: Int
    let text: String
    let locator: Locator
}

/// Extracteur de phrases léger et ultra-rapide pour l'EPUB.
///
/// Contrairement au pipeline lourd de Readium (`PublicationSpeechSynthesizer` + `SwiftSoup`),
/// cet extracteur :
/// 1. Ne bloque JAMAIS sur `positionsByReadingOrder()` (qui pagine tout le livre).
/// 2. Lit directement la ressource XHTML du chapitre demandé via `publication.get(link)`.
/// 3. Nettoie le balisage HTML en texte brut sans allouer d'arbre DOM lourd.
/// 4. Segmente le texte en phrases via Apple `NLTokenizer` en quelques millisecondes.
final class LoreChapterTextExtractor: Sendable {

    /// Extrait les phrases du chapitre à l'index donné dans la `publication`.
    func extractSentences(
        forChapterIndex chapterIndex: Int,
        in publication: Publication
    ) async -> [LoreTTSSentence] {
        guard publication.readingOrder.indices.contains(chapterIndex) else {
            return []
        }

        let link = publication.readingOrder[chapterIndex]
        guard let resource = publication.get(link),
              let rawString = (try? await resource.readAsString().get()) ?? (try? await resource.read().asString().get())
        else {
            return []
        }

        let plainText = Self.stripHTML(rawString)
        guard !plainText.isEmpty else { return [] }

        let languageCode = publication.metadata.language?.code.bcp47 ?? "fr"
        let rawSentences = Self.segmentSentences(from: plainText, languageCode: languageCode)
        guard !rawSentences.isEmpty else { return [] }

        let totalLength = max(1, plainText.count)
        let totalChapters = max(1, publication.readingOrder.count)

        var result: [LoreTTSSentence] = []
        result.reserveCapacity(rawSentences.count)

        for (index, raw) in rawSentences.enumerated() {
            let offset = raw.range.lowerBound.utf16Offset(in: plainText)
            let chapterProgression = min(1.0, max(0.0, Double(offset) / Double(totalLength)))
            let totalProgression = min(1.0, max(0.0, (Double(chapterIndex) + chapterProgression) / Double(totalChapters)))

            let locator = Locator(
                href: link.url(),
                mediaType: link.mediaType ?? .html,
                title: link.title,
                locations: Locator.Locations(
                    progression: chapterProgression,
                    totalProgression: totalProgression
                ),
                text: Locator.Text(
                    highlight: raw.text
                )
            )

            result.append(
                LoreTTSSentence(
                    chapterIndex: chapterIndex,
                    sentenceIndex: index,
                    text: raw.text,
                    locator: locator
                )
            )
        }

        return result
    }

    /// Trouve l'index de phrase le plus pertinent pour un `Locator` donné dans la liste des phrases du chapitre.
    func findStartingSentenceIndex(
        in sentences: [LoreTTSSentence],
        for locator: Locator?
    ) -> Int {
        guard let locator, !sentences.isEmpty else { return 0 }

        // 1. Recherche par correspondance textuelle dans le surlignage / snippet
        if let highlight = locator.text.highlight?.trimmingCharacters(in: .whitespacesAndNewlines),
           !highlight.isEmpty {
            let normalizedHighlight = highlight.lowercased()
            if let matched = sentences.firstIndex(where: {
                $0.text.lowercased().contains(normalizedHighlight) || normalizedHighlight.contains($0.text.lowercased())
            }) {
                return matched
            }
        }

        // 2. Recherche par progression dans le chapitre
        if let targetProgression = locator.locations.progression {
            var closestIndex = 0
            var minDiff = Double.greatestFiniteMagnitude
            for (index, item) in sentences.enumerated() {
                let itemProgression = item.locator.locations.progression ?? 0.0
                let diff = abs(itemProgression - targetProgression)
                if diff < minDiff {
                    minDiff = diff
                    closestIndex = index
                }
            }
            return closestIndex
        }

        return 0
    }

    // MARK: - Découpage en phrases avec NLTokenizer

    struct RawSentence {
        let text: String
        let range: Range<String.Index>
    }

    static func segmentSentences(from text: String, languageCode: String) -> [RawSentence] {
        let tokenizer = NLTokenizer(unit: .sentence)
        let nlLanguage: NLLanguage
        if languageCode.lowercased().hasPrefix("en") {
            nlLanguage = .english
        } else {
            nlLanguage = .french
        }
        tokenizer.setLanguage(nlLanguage)
        tokenizer.string = text

        var sentences: [RawSentence] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let rawSub = text[range]
            let trimmed = rawSub.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains(where: { $0.isLetter || $0.isNumber }) {
                sentences.append(RawSentence(text: trimmed, range: range))
            }
            return true
        }
        return sentences
    }

    // MARK: - Nettoyage HTML rapide et sans DOM lourd

    static func stripHTML(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }

        var text = raw

        // 1. Supprime les sections <head>...</head>, <style>...</style>, <script>...</script>
        text = removeTags(named: "head", in: text)
        text = removeTags(named: "style", in: text)
        text = removeTags(named: "script", in: text)

        // 2. Insère des retours à la ligne pour les balises de bloc
        let blockTags = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "br", "li", "blockquote", "tr", "section", "article"]
        for tag in blockTags {
            text = text.replacingOccurrences(of: "<\(tag)>", with: "\n", options: .caseInsensitive)
            text = text.replacingOccurrences(of: "<\(tag) ", with: "\n<", options: .caseInsensitive)
            text = text.replacingOccurrences(of: "</\(tag)>", with: "\n", options: .caseInsensitive)
            text = text.replacingOccurrences(of: "<\(tag)/>", with: "\n", options: .caseInsensitive)
            text = text.replacingOccurrences(of: "<\(tag) />", with: "\n", options: .caseInsensitive)
        }

        // 3. Supprime les balises restantes <...>
        var result = ""
        result.reserveCapacity(text.count)
        var insideTag = false
        for char in text {
            if char == "<" {
                insideTag = true
            } else if char == ">" {
                insideTag = false
            } else if !insideTag {
                result.append(char)
            }
        }

        // 4. Décodage des entités HTML standards
        result = unescapeHTMLEntities(result)

        // 5. Normalisation des espaces multiples et lignes vides
        return normalizeWhitespace(result)
    }

    private static func removeTags(named tag: String, in string: String) -> String {
        let pattern = "<" + tag + "[^>]*>[\\s\\S]*?</" + tag + ">"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return string
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: " ")
    }

    private static func unescapeHTMLEntities(_ string: String) -> String {
        var str = string
        str = str.replacingOccurrences(of: "&nbsp;", with: " ")
        str = str.replacingOccurrences(of: "&amp;", with: "&")
        str = str.replacingOccurrences(of: "&lt;", with: "<")
        str = str.replacingOccurrences(of: "&gt;", with: ">")
        str = str.replacingOccurrences(of: "&quot;", with: "\"")
        str = str.replacingOccurrences(of: "&#39;", with: "'")
        str = str.replacingOccurrences(of: "&apos;", with: "'")
        str = str.replacingOccurrences(of: "&rsquo;", with: "’")
        str = str.replacingOccurrences(of: "&lsquo;", with: "‘")
        str = str.replacingOccurrences(of: "&rdquo;", with: "”")
        str = str.replacingOccurrences(of: "&ldquo;", with: "“")
        str = str.replacingOccurrences(of: "&mdash;", with: "—")
        str = str.replacingOccurrences(of: "&ndash;", with: "–")
        str = str.replacingOccurrences(of: "&hellip;", with: "…")
        str = str.replacingOccurrences(of: "&eacute;", with: "é")
        str = str.replacingOccurrences(of: "&egrave;", with: "è")
        str = str.replacingOccurrences(of: "&ecirc;", with: "ê")
        str = str.replacingOccurrences(of: "&agrave;", with: "à")
        str = str.replacingOccurrences(of: "&ccedil;", with: "ç")
        str = str.replacingOccurrences(of: "&icirc;", with: "î")
        str = str.replacingOccurrences(of: "&ocirc;", with: "ô")
        str = str.replacingOccurrences(of: "&ucirc;", with: "û")

        // Décodage des entités numériques décimales (ex: &#8217;)
        if str.contains("&#") {
            if let regex = try? NSRegularExpression(pattern: "&#([0-9]+);") {
                let nsStr = str as NSString
                let matches = regex.matches(in: str, range: NSRange(location: 0, length: nsStr.length))
                for match in matches.reversed() {
                    let codeStr = nsStr.substring(with: match.range(at: 1))
                    if let code = UInt32(codeStr), let scalar = UnicodeScalar(code) {
                        let replacement = String(Character(scalar))
                        str = (str as NSString).replacingCharacters(in: match.range, with: replacement)
                    }
                }
            }
        }

        return str
    }

    private static func normalizeWhitespace(_ string: String) -> String {
        let lines = string.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                cleanedLines.append(trimmed)
            }
        }
        return cleanedLines.joined(separator: "\n")
    }
}
