import Foundation
import SwiftData

@MainActor
final class PodcastRepository {
    private let context: ModelContext
    private let saveContext: (ModelContext) throws -> Void

    init(
        context: ModelContext,
        save: ((ModelContext) throws -> Void)? = nil
    ) {
        self.context = context
        saveContext = save ?? { try $0.save() }
    }

    func add(_ podcast: PodcastRecord) throws {
        context.insert(podcast)
        do {
            try saveContext(context)
        } catch {
            context.delete(podcast)
            throw error
        }
    }

    func podcasts() throws -> [PodcastRecord] {
        let ready = PodcastImportState.ready.rawValue
        var descriptor = FetchDescriptor<PodcastRecord>(
            predicate: #Predicate { $0.importStateRawValue == ready }
        )
        descriptor.sortBy = [SortDescriptor(\.importedAt, order: .reverse)]
        return try context.fetch(descriptor)
    }

    func podcast(id: UUID) throws -> PodcastRecord? {
        var descriptor = FetchDescriptor<PodcastRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func podcast(contentSHA256: String) throws -> PodcastRecord? {
        var descriptor = FetchDescriptor<PodcastRecord>(
            predicate: #Predicate { $0.contentSHA256 == contentSHA256 }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func pendingImports() throws -> [PodcastRecord] {
        let pending = PodcastImportState.pending.rawValue
        let descriptor = FetchDescriptor<PodcastRecord>(
            predicate: #Predicate { $0.importStateRawValue == pending }
        )
        return try context.fetch(descriptor)
    }

    func confirmImport(podcastID: UUID, relativeFilePath: String) throws {
        guard let podcast = try podcast(id: podcastID) else {
            throw PodcastRepositoryError.podcastNotFound
        }
        podcast.relativeFilePath = relativeFilePath
        podcast.importState = .ready
        podcast.stagingToken = nil
        try saveContext(context)
    }

    func markRecoveryRequired(podcastID: UUID) throws {
        guard let podcast = try podcast(id: podcastID) else {
            throw PodcastRepositoryError.podcastNotFound
        }
        podcast.importState = .recoveryRequired
        try saveContext(context)
    }

    func savePosition(
        for podcastID: UUID,
        seconds: Double,
        updatedAt: Date = .now
    ) throws {
        guard let podcast = try podcast(id: podcastID) else {
            throw PodcastRepositoryError.podcastNotFound
        }
        let previousPosition = podcast.lastPositionSeconds
        let previousUpdatedAt = podcast.progressUpdatedAt
        let maximum = podcast.durationSeconds ?? .greatestFiniteMagnitude
        podcast.lastPositionSeconds = min(max(seconds, 0), maximum)
        podcast.progressUpdatedAt = updatedAt
        do {
            try saveContext(context)
        } catch {
            podcast.lastPositionSeconds = previousPosition
            podcast.progressUpdatedAt = previousUpdatedAt
            throw error
        }
    }

    func delete(_ podcast: PodcastRecord) throws {
        context.delete(podcast)
        do {
            try saveContext(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

enum PodcastRepositoryError: LocalizedError, Equatable {
    case podcastNotFound

    var errorDescription: String? {
        switch self {
        case .podcastNotFound:
            "Le podcast demandé n’existe plus dans la bibliothèque."
        }
    }
}
