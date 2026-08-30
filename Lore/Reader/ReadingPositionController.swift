import Foundation
import ReadiumShared

@MainActor
final class ReadingPositionController {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private struct PendingPosition {
        let locator: Locator
        let revision: UInt64
    }

    private let bookID: UUID
    private let store: any ReaderProgressStore
    private let debounceDuration: Duration
    private let sleep: Sleep
    private let onError: @MainActor (Error) -> Void
    private var pendingPosition: PendingPosition?
    private var nextRevision: UInt64 = 0
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
        nextRevision &+= 1
        pendingPosition = PendingPosition(locator: locator, revision: nextRevision)
        pendingSave?.cancel()
        pendingSave = Task { [weak self, sleep, debounceDuration] in
            do {
                try await sleep(debounceDuration)
                guard !Task.isCancelled else { return }
                try self?.savePending()
            } catch is CancellationError {
                // A newer position or explicit flush owns the next attempt.
            } catch {
                self?.onError(error)
            }
        }
    }

    func flush(currentLocator: Locator? = nil) async throws {
        pendingSave?.cancel()
        pendingSave = nil
        if let currentLocator { recordWithoutDebounce(currentLocator) }
        try savePending()
    }

    private func recordWithoutDebounce(_ locator: Locator) {
        nextRevision &+= 1
        pendingPosition = PendingPosition(locator: locator, revision: nextRevision)
    }

    private func savePending() throws {
        guard let pending = pendingPosition else { return }
        let stored = try LocatorPersistenceCodec.encode(pending.locator)
        try store.saveLocator(
            stored,
            progression: pending.locator.locations.totalProgression,
            for: bookID
        )
        if pendingPosition?.revision == pending.revision { pendingPosition = nil }
    }
}
