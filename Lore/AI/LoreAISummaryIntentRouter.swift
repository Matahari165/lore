import Foundation

struct LoreAISummaryIntentRouter: Sendable {
    func route(_ input: String) -> LoreAISummaryScope? {
        let normalized = input.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let asksForSummary = ["resume", "resumer", "recap", "recapitule", "summary", "summarize", "summarise"]
            .contains { normalized.contains($0) }
        guard asksForSummary else { return nil }

        if ["hier", "yesterday"].contains(where: normalized.contains) {
            return .yesterday
        }
        if ["derniere session", "derniere seance", "last session", "previous session"]
            .contains(where: normalized.contains) {
            return .sinceLastSession
        }
        if ["chapitre", "chapter"].contains(where: normalized.contains) {
            return .currentChapter
        }
        return nil
    }
}
