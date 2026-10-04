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

/// Extracteur de phrases léger, ultra-rapide et linguistiquement robuste pour l'EPUB.
///
/// Contrairement au pipeline lourd de Readium (`PublicationSpeechSynthesizer` + `SwiftSoup`),
/// cet extracteur :
/// 1. Ne bloque JAMAIS sur `positionsByReadingOrder()` (qui pagine tout le livre).
/// 2. Lit directement la ressource XHTML du chapitre demandé via `publication.get(link)`.
/// 3. Nettoie le balisage HTML en texte brut sans allouer d'arbre DOM lourd.
/// 4. Décode toutes les entités HTML (nommées, décimales et hexadécimales).
/// 5. Segmente le texte en phrases via Apple `NLTokenizer` avec préservation des incises de dialogue
///    et des abréviations courantes (Dr., M., Mme., etc.).
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

        let totalUTF16Length = max(1, plainText.utf16.count)
        let totalChapters = max(1, publication.readingOrder.count)

        var result: [LoreTTSSentence] = []
        result.reserveCapacity(rawSentences.count)

        for (index, raw) in rawSentences.enumerated() {
            let offset = raw.range.lowerBound.utf16Offset(in: plainText)
            let chapterProgression = min(1.0, max(0.0, Double(offset) / Double(totalUTF16Length)))
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
        if let highlight = (locator.text.highlight ?? locator.text.after)?.trimmingCharacters(in: .whitespacesAndNewlines),
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

    // MARK: - Découpage en phrases avec NLTokenizer enrichi

    struct RawSentence {
        let text: String
        let range: Range<String.Index>
    }

    private static let frAbbreviations: Set<String> = [
        "dr.", "dr", "m.", "mme.", "mme", "mlle.", "mlle", "me.", "mgr.", "col.", "cap.", "gen.", "st.", "ste.", "av.", "prof.", "cf.", "vol.", "fasc."
    ]
    private static let enAbbreviations: Set<String> = [
        "st.", "gen.", "col.", "capt.", "lt.", "sgt.", "hon.", "gov.", "sen.", "rev.", "prof.", "dr.", "dr", "mr.", "mr", "mrs.", "mrs", "ms.", "ms"
    ]

    static func segmentSentences(from text: String, languageCode: String) -> [RawSentence] {
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        let isEnglish = languageCode.lowercased().hasPrefix("en")
        tokenizer.setLanguage(isEnglish ? .english : .french)
        tokenizer.string = text

        var rawTokens: [(text: Substring, range: Range<String.Index>)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            rawTokens.append((text[range], range))
            return true
        }

        let abbreviations = isEnglish ? enAbbreviations : frAbbreviations
        var merged: [(text: String, range: Range<String.Index>)] = []

        for token in rawTokens {
            let trimmed = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let hasAlphanumeric = trimmed.contains(where: { $0.isLetter || $0.isNumber })

            // 1. Ponctuation isolée (ex: "»", '"') rattachée à la phrase précédente
            if !hasAlphanumeric {
                if let last = merged.popLast() {
                    let combinedRange = last.range.lowerBound..<token.range.upperBound
                    let combinedText = last.text + " " + trimmed
                    merged.append((combinedText, combinedRange))
                }
                continue
            }

            // 2. Fusion si incise de dialogue (minuscule) ou terminaison par abréviation
            var shouldMerge = false
            if let last = merged.last {
                let lastTrimmed = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let lastWord = lastTrimmed.split(separator: " ").last?.lowercased() ?? ""
                if abbreviations.contains(lastWord) {
                    shouldMerge = true
                }

                if !shouldMerge {
                    let firstLetter = trimmed.first(where: { $0.isLetter })
                    if let firstLetter, firstLetter.isLowercase {
                        shouldMerge = true
                    }
                }
            }

            if shouldMerge, let last = merged.popLast() {
                let combinedRange = last.range.lowerBound..<token.range.upperBound
                let combinedText = String(text[combinedRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                merged.append((combinedText, combinedRange))
            } else {
                merged.append((trimmed, token.range))
            }
        }

        return merged.map { RawSentence(text: $0.text, range: $0.range) }
    }

    // MARK: - Nettoyage HTML ultra-rapide

    private static let headStyleScriptRegex = try! NSRegularExpression(
        pattern: "<(head|style|script)[^>]*>[\\s\\S]*?</\\1>",
        options: [.caseInsensitive]
    )
    private static let blockTagRegex = try! NSRegularExpression(
        pattern: "</?(?:p|div|h[1-6]|br|hr|li|blockquote|tr|td|th|table|tbody|thead|tfoot|section|article|aside|header|footer|nav|main|figure|figcaption|dd|dt|dl|pre)(?:[\\s/][^>]*)?>",
        options: [.caseInsensitive]
    )
    private static let adjacentTagsRegex = try! NSRegularExpression(
        pattern: "(</[a-zA-Z0-9]+>)(<[a-zA-Z0-9]+)",
        options: []
    )

    static func stripHTML(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }

        // 1. Suppression head, style, script
        let nsRaw = raw as NSString
        let noHead = headStyleScriptRegex.stringByReplacingMatches(
            in: raw,
            options: [],
            range: NSRange(location: 0, length: nsRaw.length),
            withTemplate: " "
        )

        // 2. Retours à la ligne pour toutes les balises de bloc
        let nsNoHead = noHead as NSString
        let blockSeparated = blockTagRegex.stringByReplacingMatches(
            in: noHead,
            options: [],
            range: NSRange(location: 0, length: nsNoHead.length),
            withTemplate: "\n"
        )

        // 3. Espace de sécurité entre balises imbriquées collées (ex: </span><span>)
        let nsBlocks = blockSeparated as NSString
        let tagsSpaced = adjacentTagsRegex.stringByReplacingMatches(
            in: blockSeparated,
            options: [],
            range: NSRange(location: 0, length: nsBlocks.length),
            withTemplate: "$1 $2"
        )

        // 4. Suppression des balises inline restantes
        var result = ""
        result.reserveCapacity(tagsSpaced.count)
        var insideTag = false
        for char in tagsSpaced {
            if char == "<" {
                insideTag = true
            } else if char == ">" {
                insideTag = false
            } else if !insideTag {
                result.append(char)
            }
        }

        // 5. Décodage single-pass des entités HTML (numériques & nommées)
        let decoded = decodeHTMLEntities(result)

        // 6. Normalisation rapide des espaces et lignes
        var cleanedLines: [Substring] = []
        for line in decoded.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                cleanedLines.append(Substring(trimmed))
            }
        }
        return cleanedLines.joined(separator: "\n")
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        result.reserveCapacity(string.count)
        var index = string.startIndex
        while index < string.endIndex {
            if string[index] == "&" {
                if let semicolon = string[index...].prefix(12).firstIndex(of: ";") {
                    let entity = string[index...semicolon]
                    if let decoded = decodeSingleEntity(entity) {
                        result.append(decoded)
                        index = string.index(after: semicolon)
                        continue
                    }
                }
            }
            result.append(string[index])
            index = string.index(after: index)
        }
        return result
    }

    private static func decodeSingleEntity(_ entity: Substring) -> String? {
        let inner = entity.dropFirst().dropLast()
        if inner.hasPrefix("#") {
            let numStr = inner.dropFirst()
            if numStr.hasPrefix("x") || numStr.hasPrefix("X") {
                let hexStr = numStr.dropFirst()
                if let code = UInt32(hexStr, radix: 16), let scalar = UnicodeScalar(code) {
                    return String(Character(scalar))
                }
            } else {
                if let code = UInt32(numStr, radix: 10), let scalar = UnicodeScalar(code) {
                    return String(Character(scalar))
                }
            }
            return nil
        }

        switch inner {
        case "nbsp", "thinsp", "ensp", "emsp": return " "
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "shy": return ""
        case "laquo": return "«"
        case "raquo": return "»"
        case "lsaquo": return "‹"
        case "rsaquo": return "›"
        case "ldquo": return "“"
        case "rdquo": return "”"
        case "lsquo": return "‘"
        case "rsquo": return "’"
        case "mdash": return "—"
        case "ndash": return "–"
        case "minus": return "−"
        case "hellip": return "…"
        case "bull": return "•"
        case "middot": return "·"
        case "oelig": return "œ"
        case "OElig": return "Œ"
        case "aelig": return "æ"
        case "AElig": return "Æ"
        case "eacute": return "é"
        case "Eacute": return "É"
        case "egrave": return "è"
        case "Egrave": return "È"
        case "ecirc": return "ê"
        case "Ecirc": return "Ê"
        case "euml": return "ë"
        case "Euml": return "Ë"
        case "agrave": return "à"
        case "Agrave": return "À"
        case "acirc": return "â"
        case "Acirc": return "Â"
        case "ccedil": return "ç"
        case "Ccedil": return "Ç"
        case "icirc": return "î"
        case "Icirc": return "Î"
        case "iuml": return "ï"
        case "Iuml": return "Ï"
        case "ocirc": return "ô"
        case "Ocirc": return "Ô"
        case "ucirc": return "û"
        case "Ucirc": return "Û"
        case "uuml": return "ü"
        case "Uuml": return "Ü"
        case "copy": return "©"
        case "reg": return "®"
        case "trade": return "™"
        default: return nil
        }
    }
}
