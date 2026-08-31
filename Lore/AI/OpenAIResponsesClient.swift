import Foundation

struct OpenAIResponsesConfiguration: Sendable {
    static let model = "gpt-5.6-luna"

    var endpoint = URL(string: "https://api.openai.com/v1/responses")!
    var requestTimeout: TimeInterval = 45
    var resourceTimeout: TimeInterval = 90
}

final class OpenAIResponsesClient: LoreAIService, @unchecked Sendable {
    private let keyStore: any OpenAIAPIKeyStore
    private let session: URLSession
    private let configuration: OpenAIResponsesConfiguration
    let promptBuilder: LoreAIPromptBuilder
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        keyStore: any OpenAIAPIKeyStore = KeychainOpenAIAPIKeyStore(),
        session: URLSession? = nil,
        configuration: OpenAIResponsesConfiguration = .init(),
        promptBuilder: LoreAIPromptBuilder = .init()
    ) {
        self.keyStore = keyStore
        self.configuration = configuration
        self.promptBuilder = promptBuilder
        if let session {
            self.session = session
        } else {
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
            sessionConfiguration.timeoutIntervalForResource = configuration.resourceTimeout
            sessionConfiguration.waitsForConnectivity = false
            sessionConfiguration.urlCache = nil
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    func explain(_ context: BookAIContext) async throws -> String {
        try await respond(to: promptBuilder.explanation(for: context))
    }

    func recap(_ context: PreviousReadingContext) async throws -> String {
        try await respond(to: promptBuilder.previousReadingRecap(for: context))
    }

    func chat(_ context: LoreAIChatContext) async throws -> String {
        try await respond(to: LoreAIChatPromptBuilder().chat(for: context))
    }

    func respond(to prompt: LoreAIPrompt) async throws -> String {
        guard let rawKey = try keyStore.loadAPIKey() else { throw LoreAIError.missingAPIKey }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LoreAIError.invalidAPIKey }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            ResponsesRequest(
                model: OpenAIResponsesConfiguration.model,
                store: false,
                reasoning: .init(effort: "low"),
                input: [.init(role: "developer", content: prompt.developer)]
                    + prompt.history.map { .init(role: $0.role.rawValue, content: $0.text) }
                    + [.init(role: "user", content: prompt.user)]
            )
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LoreAIError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                let error = try? decoder.decode(APIErrorEnvelope.self, from: data)
                throw LoreAIError.requestFailed(statusCode: http.statusCode, message: error?.error.message)
            }
            let envelope = try decoder.decode(ResponsesEnvelope.self, from: data)
            guard let text = envelope.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { throw LoreAIError.invalidResponse }
            return text
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LoreAIError {
            throw error
        } catch let error as DecodingError {
            _ = error
            throw LoreAIError.invalidResponse
        } catch {
            throw LoreAIError.transport(error.localizedDescription)
        }
    }
}

private struct ResponsesRequest: Encodable {
    struct Reasoning: Encodable { let effort: String }
    struct Input: Encodable { let role: String; let content: String }
    let model: String
    let store: Bool
    let reasoning: Reasoning
    let input: [Input]
}

private struct ResponsesEnvelope: Decodable {
    struct Output: Decodable {
        struct Content: Decodable {
            let type: String?
            let text: String?
        }
        let type: String?
        let content: [Content]?
    }

    let outputText: String?
    let output: [Output]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var extractedText: String? {
        if let outputText, !outputText.isEmpty { return outputText }
        var parts: [String] = []
        for item in output ?? [] {
            for content in item.content ?? [] where content.type == nil || content.type == "output_text" {
                if let text = content.text {
                    parts.append(text)
                }
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String? }
    let error: APIError
}
