import Testing
@testable import Lore

struct LoreAISummaryIntentRouterTests {
    private let router = LoreAISummaryIntentRouter()

    @Test(arguments: ["Résume ce chapitre", "Peux-tu résumer le chapitre ?", "Summarize this chapter"])
    func routesCurrentChapter(_ input: String) {
        #expect(router.route(input) == .currentChapter)
    }

    @Test(arguments: ["Résume ce que j’ai lu hier", "Récapitule ma lecture d'hier", "Summarize what I read yesterday"])
    func routesYesterday(_ input: String) {
        #expect(router.route(input) == .yesterday)
    }

    @Test(arguments: ["Résume depuis ma dernière session", "Recap my last session", "Summarise my previous session"])
    func routesLastSession(_ input: String) {
        #expect(router.route(input) == .sinceLastSession)
    }

    @Test func leavesOrdinaryQuestionsAlone() {
        #expect(router.route("Pourquoi ce personnage hésite-t-il ?") == nil)
        #expect(router.route("Que signifie le mot chapitre ici ?") == nil)
        #expect(router.route("Résume le livre entier") == nil)
    }
}
