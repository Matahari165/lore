import Foundation
import ReadiumShared

@MainActor
final class ReadingPositionController {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let bookID: UUID
    private let store: any ReaderProgressStore
    private let debounceDuration: Duration
    private let sleep: Sleep
    private let onError: @MainActor (Error) -> Void

    private var latestLocator: Locator?
    private var pendingSave: Task<Void, Never>?

    init(
        bookID: UUID,
        store: any ReaderProgressStore,
        debounceDuration: Duration = .seconds(1),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.bookID = bookID
        self.store = store
        self.debounceDuration = debounceDuration
        self.sleep = sleep
        self.onError = onError
    }

    func record(_ locator: Locator) {
        latestLocator = locator
        pendingSave?.cancel()
        pendingSave = Task { [weak self, sleep, debounceDuration] in
            do {
                try await sleep(debounceDuration)
                guard !Task.isCancelled else { return }
                await self?.saveLatest()
            } catch is CancellationError {
                // A newer location or an explicit flush superseded this save.
            } catch {
                self?.onError(error)
            }
        }
    }

    func flush(currentLocator: Locator? = nil) async {
        pendingSave?.cancel()
        pendingSave = nil
        if let currentLocator {
            latestLocator = currentLocator
        }
        await saveLatest()
    }

    private func saveLatest() async {
        guard let latestLocator else { return }
        do {
            let data = try LocatorJSONCodec.encode(latestLocator)
            try store.saveLocatorData(
                data,
                progression: latestLocator.locations.totalProgression,
                for: bookID
            )
        } catch {
            onError(error)
        }
    }
}
