import Foundation

protocol LoreAILibraryService: Sendable {
    func libraryChat(_ context: LoreAILibraryContext) async throws -> String
}

extension OpenAIResponsesClient: LoreAILibraryService {
    func libraryChat(_ context: LoreAILibraryContext) async throws -> String {
        try await respond(to: LoreAILibraryPromptBuilder().prompt(for: context))
    }
}
