import Foundation

extension OpenAIResponsesClient: LoreAIAdvancedService {
    func summarizeChapter(_ context: LoreAIChapterContext) async throws -> String {
        try await respond(to: LoreAIAdvancedPromptBuilder().chapterSummary(for: context))
    }

    func answerQuestion(_ context: LoreAIQuestionContext) async throws -> String {
        try await respond(to: LoreAIAdvancedPromptBuilder().answerQuestion(for: context))
    }

    func discussEnding(_ context: LoreAIEndingDiscussionContext) async throws -> String {
        try await respond(to: LoreAIAdvancedPromptBuilder().endingDiscussion(for: context))
    }
}
