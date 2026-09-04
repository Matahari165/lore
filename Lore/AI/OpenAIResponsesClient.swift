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

    func chat(_ context: LoreAIChatContext) async throws -> LoreAIChatResponse {
        let prepared = try LoreAIChatPromptBuilder().preparedChat(for: context)
        let data = try await respondData(to: prepared.prompt, structuredChat: true)
        let payload: StructuredChatPayload
        do {
            payload = try decoder.decode(StructuredChatPayload.self, from: data)
        } catch {
            throw LoreAIError.invalidResponse
        }
        let answer = payload.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw LoreAIError.invalidResponse }

        var allowed: [String: LoreAIChatSource] = [:]
        var duplicated = Set<String>()
        for source in prepared.sources {
            if let pair: (String, LoreAIChatSource) = ({ source -> (String, LoreAIChatSource)? in
                guard context.bookID == source.bookID,
                      source.hasValidIdentityAndProgression,
                      source.locatorSchemaVersion == LocatorPersistenceCodec.currentSchemaVersion,
                      source.progression.map({ progression in
                          guard let frontier = context.readFrontierProgression else {
                              return context.stage == .finished
                          }
                          return progression <= frontier + 0.000_001
                      }) == true,
                      (try? LocatorPersistenceCodec.decode(.init(
                          data: source.locatorJSON,
                          schemaVersion: source.locatorSchemaVersion
                      ))) != nil
                else { return nil }
                return (source.id, source)
            })(source) {
                if allowed.updateValue(pair.1, forKey: pair.0) != nil { duplicated.insert(pair.0) }
            }
        }
        for id in duplicated { allowed.removeValue(forKey: id) }
        var seen = Set<String>()
        let sources = payload.sourceIDs.compactMap { id -> LoreAIChatSource? in
            guard seen.insert(id).inserted else { return nil }
            return allowed[id]
        }
        return LoreAIChatResponse(text: answer, sources: sources)
    }

    func respond(to prompt: LoreAIPrompt) async throws -> String {
        let data = try await respondData(to: prompt, structuredChat: false)
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { throw LoreAIError.invalidResponse }
        return text
    }

    private func respondData(to prompt: LoreAIPrompt, structuredChat: Bool) async throws -> Data {
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
                text: structuredChat ? .structuredChat : nil,
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
            guard envelope.status == nil || envelope.status == "completed",
                  !envelope.containsRefusal
            else { throw LoreAIError.invalidResponse }
            guard let text = envelope.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { throw LoreAIError.invalidResponse }
            return Data(text.utf8)
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
    struct TextConfiguration: Encodable {
        struct Format: Encodable {
            let type: String
            let name: String
            let strict: Bool
            let schema: JSONSchema
        }
        struct JSONSchema: Encodable {
            struct Property: Encodable {
                let type: String
                let items: Item?
                struct Item: Encodable { let type: String }

                enum CodingKeys: String, CodingKey { case type, items }
                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(type, forKey: .type)
                    try container.encodeIfPresent(items, forKey: .items)
                }
            }
            let type = "object"
            let properties: [String: Property]
            let required = ["answer", "source_ids"]
            let additionalProperties = false
        }
        let format: Format

        static let structuredChat = TextConfiguration(format: .init(
            type: "json_schema",
            name: "lore_chat_answer",
            strict: true,
            schema: .init(properties: [
                "answer": .init(type: "string", items: nil),
                "source_ids": .init(type: "array", items: .init(type: "string"))
            ])
        ))
    }
    let model: String
    let store: Bool
    let reasoning: Reasoning
    let text: TextConfiguration?
    let input: [Input]
}

private struct StructuredChatPayload: Decodable {
    let answer: String
    let sourceIDs: [String]

    enum CodingKeys: String, CodingKey {
        case answer
        case sourceIDs = "source_ids"
    }
}

private struct ResponsesEnvelope: Decodable {
    struct Output: Decodable {
        struct Content: Decodable {
            let type: String?
            let text: String?
            let refusal: String?
        }
        let type: String?
        let content: [Content]?
    }

    let outputText: String?
    let output: [Output]?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
        case status
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

    var containsRefusal: Bool {
        output?.contains { item in
            item.content?.contains { $0.type == "refusal" || $0.refusal != nil } == true
        } == true
    }
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String? }
    let error: APIError
}
