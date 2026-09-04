import Foundation
import SwiftData
import Testing
@testable import Lore

@MainActor
struct PodcastRepositoryTests {
    @Test func storesPodcastsNewestFirst() throws {
        let fixture = try Fixture()
        let older = PodcastRecord(
            title: "Ancien",
            originalFilename: "ancien.mp4",
            relativeFilePath: "Podcasts/ancien/episode.mp4",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = PodcastRecord(
            title: "Récent",
            originalFilename: "recent.mp4",
            relativeFilePath: "Podcasts/recent/episode.mp4",
            importedAt: Date(timeIntervalSince1970: 2)
        )

        try fixture.repository.add(older)
        try fixture.repository.add(newer)

        #expect(try fixture.repository.podcasts().map(\.title) == ["Récent", "Ancien"])
    }

    @Test func savesPositionAndClampsItToThePodcastDuration() throws {
        let fixture = try Fixture()
        let podcast = PodcastRecord(
            title: "Épisode",
            originalFilename: "episode.mp4",
            relativeFilePath: "Podcasts/episode/episode.mp4",
            durationSeconds: 1_800
        )
        try fixture.repository.add(podcast)

        try fixture.repository.savePosition(for: podcast.id, seconds: 600)
        #expect(try fixture.repository.podcast(id: podcast.id)?.lastPositionSeconds == 600)
        #expect(try fixture.repository.podcast(id: podcast.id)?.progression == 1.0 / 3.0)

        try fixture.repository.savePosition(for: podcast.id, seconds: 2_000)
        #expect(try fixture.repository.podcast(id: podcast.id)?.lastPositionSeconds == 1_800)
    }

    @Test func rejectsPositionForMissingPodcast() throws {
        let fixture = try Fixture()

        #expect(throws: PodcastRepositoryError.podcastNotFound) {
            try fixture.repository.savePosition(for: UUID(), seconds: 600)
        }
    }

    @Test func recoverableImportsIncludesPendingAndRecoveryRequired() throws {
        let fixture = try Fixture()
        let ready = PodcastRecord(title: "Prêt", originalFilename: "ready.mp4", relativeFilePath: "Podcasts/ready/episode.mp4")
        let pending = PodcastRecord(title: "Attente", originalFilename: "pending.mp4", relativeFilePath: "", importState: .pending)
        let recovery = PodcastRecord(title: "Reprise", originalFilename: "recovery.mp4", relativeFilePath: "", importState: .recoveryRequired)
        try fixture.repository.add(ready)
        try fixture.repository.add(pending)
        try fixture.repository.add(recovery)

        #expect(Set(try fixture.repository.recoverableImports().map(\.id)) == [pending.id, recovery.id])
        #expect(Set(try fixture.repository.allPodcasts().map(\.id)) == [ready.id, pending.id, recovery.id])
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let repository: PodcastRepository

        init() throws {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try ModelContainer(for: PodcastRecord.self, configurations: configuration)
            repository = PodcastRepository(context: container.mainContext)
        }
    }
}
