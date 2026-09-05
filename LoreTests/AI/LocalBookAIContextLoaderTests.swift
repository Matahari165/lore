import Foundation
import Testing
@testable import Lore

struct LocalBookAIContextLoaderTests {
    @Test func unavailableSnapshotNeverClaimsBookTextWasLoaded() {
        let bookID = UUID()
        let snapshot = LocalBookAIContextLoader.Snapshot(
            bookID: bookID,
            title: "Livre",
            author: nil,
            stage: .inProgress,
            chapterTitle: nil,
            frontierProgression: 0.4,
            frontierDescription: "Progression sauvegardée : 40 %",
            excerpts: [],
            isAvailable: false,
            unavailableMessage: "EPUB indisponible"
        )

        let context = snapshot.chatContext(
            summaryScope: nil,
            question: "Résume tout ce que j’ai lu jusque-là",
            history: []
        )

        #expect(context.bookID == bookID)
        #expect(context.excerpts.isEmpty)
        #expect(context.readFrontierProgression == 0.4)
        #expect(context.fullBookAccessGranted == false)
    }

    @Test func firstReadingSummaryKeepsTheDefaultScopeUnrestrictedByChapterIntent() {
        let router = LoreAISummaryIntentRouter()

        #expect(router.route("Résume tout ce que j’ai lu jusque-là dans ce livre") == nil)
        #expect(router.route("Résume le chapitre que je viens de lire") == .currentChapter)
    }
}
