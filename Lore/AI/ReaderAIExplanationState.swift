import Foundation

enum ReaderAIExplanationState: Identifiable, Equatable {
    case loading(selectedText: String)
    case answer(selectedText: String, text: String)
    case failure(selectedText: String, message: String)

    var id: String { "reader-ai-explanation" }

    var selectedText: String {
        switch self {
        case let .loading(selectedText), let .answer(selectedText, _), let .failure(selectedText, _):
            selectedText
        }
    }
}

enum ReaderAIRecapState: Identifiable, Equatable {
    case loading
    case answer(String)
    case failure(String)

    var id: String { "reader-ai-daily-recap" }
}
