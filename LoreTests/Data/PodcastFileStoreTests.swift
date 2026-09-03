import Foundation
import Testing
@testable import Lore

struct PodcastFileStoreTests {
    @Test func hashesAndPromotesTheExactStagedCopy() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "episode.mp4", contents: "original")

        let staged = try fixture.store.stageMP4(from: source)
        try Data("changed".utf8).write(to: source)

        #expect(try Data(contentsOf: staged.fileURL) == Data("original".utf8))
        #expect(try fixture.store.contentSHA256(of: staged.fileURL) == staged.contentSHA256)
        let path = try fixture.store.promote(staged, to: fixture.podcastID)
        #expect(path == "Podcasts/\(fixture.podcastID.uuidString)/episode.mp4")
        #expect(try Data(contentsOf: fixture.store.fileURL(for: path)) == Data("original".utf8))
    }

    @Test func removesOnlyOldUnreferencedStaging() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let old = try fixture.store.stageMP4(from: fixture.source(named: "old.mp4", contents: "old"))
        let recent = try fixture.store.stageMP4(from: fixture.source(named: "recent.mp4", contents: "recent"))
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-100)],
            ofItemAtPath: old.fileURL.deletingLastPathComponent().path
        )

        let report = try fixture.store.reconcile(
            referencedPodcastIDs: [],
            referencedStagingTokens: [recent.token],
            now: now,
            staleAfter: 10
        )

        #expect(report.removedStagingTokens == [old.token])
        #expect(FileManager.default.fileExists(atPath: recent.fileURL.path))
    }

    @Test func rejectsMutatedStagingAndKeepsItForRecovery() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let staged = try fixture.store.stageMP4(from: fixture.source(named: "mutated.mp4", contents: "original"))
        try Data("tampered".utf8).write(to: staged.fileURL)

        #expect(throws: PodcastFileStoreError.invalidStagingToken) {
            try fixture.store.promote(staged, to: fixture.podcastID)
        }
        #expect(FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    private struct Fixture {
        let root: URL
        let sourceRoot: URL
        let support: URL
        let store: PodcastFileStore
        let podcastID = UUID()

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            sourceRoot = root.appendingPathComponent("Source")
            support = root.appendingPathComponent("Support")
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            store = try PodcastFileStore(applicationSupportURL: support)
        }

        func source(named name: String, contents: String) throws -> URL {
            let url = sourceRoot.appendingPathComponent(name)
            try Data(contents.utf8).write(to: url)
            return url
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
