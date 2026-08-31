import Testing
@testable import Lore

struct LoreAIChatPromptBuilderTests {
    @Test func summaryRequestsShortMarkdownAndDropsPotentiallyLaterHistory() throws {
        let prompt = try LoreAIChatPromptBuilder().chat(for: LoreAIChatContext(
            title: "Livre",
            stage: .inProgress,
            chapterTitle: "Chapitre 2",
            readFrontierProgression: 0.4,
            excerpts: [.init(text: "Texte effectivement lu", progression: 0.4)],
            summaryScope: .currentChapter,
            history: [.init(role: .assistant, text: "Information d'un ancien tour")],
            question: "Résume ce chapitre"
        ))

        #expect(prompt.developer.contains("résumé court"))
        #expect(prompt.developer.contains("5 à 6 puces"))
        #expect(prompt.history.isEmpty)
        #expect(!prompt.user.contains("Information d'un ancien tour"))
    }

    @Test func insufficientSummaryContextIsExplicitlyConstrained() throws {
        let prompt = try LoreAIChatPromptBuilder().chat(for: LoreAIChatContext(
            title: "Livre",
            stage: .inProgress,
            readFrontierProgression: 0.2,
            summaryScope: .yesterday,
            question: "Résume hier"
        ))

        #expect(prompt.user.contains("Aucun extrait"))
        #expect(prompt.developer.contains("contexte local est insuffisant"))
    }
}
