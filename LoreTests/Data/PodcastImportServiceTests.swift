import Foundation
import SwiftData
import Testing
@testable import Lore

@MainActor
struct PodcastImportServiceTests {
    @Test func importsValidatedStagingAndLeavesAReadyRecord() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "Episode-un.mp4", contents: "valid")

        let result = try await fixture.service.importMP4(from: source)

        #expect(result == .imported)
        let podcast = try #require(try fixture.repository.podcasts().first)
        #expect(podcast.importState == .ready)
        #expect(podcast.stagingToken == nil)
        let stored = try fixture.store.fileURL(for: podcast.relativeFilePath)
        #expect(try Data(contentsOf: stored) == Data("valid".utf8))
        #expect(try FileManager.default.contentsOfDirectory(
            at: fixture.support.appendingPathComponent("Podcasts/.staging"),
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test func duplicateBytesReturnExistingPodcastWithoutValidatingAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = try fixture.source(named: "first.mp4", contents: "same")
        let second = try fixture.source(named: "second.mp4", contents: "same")

        let firstResult = try await fixture.service.importMP4(from: first)
        let secondResult = try await fixture.service.importMP4(from: second)

        #expect(firstResult == .imported)
        #expect(secondResult == .alreadyImported)
        #expect(fixture.validator.validationCount == 1)
        #expect(try fixture.repository.podcasts().count == 1)
    }

    @Test func failedReservationDiscardsStaging() async throws {
        let fixture = try Fixture(save: { _ in throw TestSaveError.failed })
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "failure.mp4", contents: "valid")

        await #expect(throws: TestSaveError.self) {
            _ = try await fixture.service.importMP4(from: source)
        }

        let staging = fixture.support.appendingPathComponent("Podcasts/.staging")
        #expect(try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func launchReconciliationPromotesPendingStaging() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let staged = try fixture.store.stageMP4(from: fixture.source(named: "pending.mp4", contents: "pending"))
        let pending = PodcastRecord(
            contentSHA256: staged.contentSHA256,
            title: "En attente",
            originalFilename: "pending.mp4",
            relativeFilePath: "",
            importState: .pending,
            stagingToken: staged.token
        )
        try fixture.repository.add(pending)

        let report = try fixture.service.reconcileImports()

        #expect(report.removedStagingTokens.isEmpty)
        #expect(pending.importState == .ready)
        #expect(pending.stagingToken == nil)
        #expect(try fixture.store.fileURL(for: pending.relativeFilePath).lastPathComponent == "episode.mp4")
    }

    @Test func recoveryRequiredImportIsRetriedOnTheNextLaunch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let token = UUID()
        let bytes = Data("recovered".utf8)
        let source = try fixture.source(named: "recovered.mp4", contents: "recovered")
        let digest = try fixture.store.contentSHA256(of: source)
        let recovery = PodcastRecord(
            contentSHA256: digest,
            title: "À récupérer",
            originalFilename: "recovered.mp4",
            relativeFilePath: "",
            importState: .recoveryRequired,
            stagingToken: token
        )
        try fixture.repository.add(recovery)

        let firstReport = try fixture.service.reconcileImports()
        #expect(firstReport.missingPodcastIDs.contains(recovery.id))
        #expect(recovery.importState == .recoveryRequired)

        let stagingDirectory = fixture.support
            .appendingPathComponent("Podcasts/.staging")
            .appendingPathComponent(token.uuidString)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try bytes.write(to: stagingDirectory.appendingPathComponent("episode.mp4"))

        let secondReport = try fixture.service.reconcileImports()
        #expect(!secondReport.missingPodcastIDs.contains(recovery.id))
        #expect(recovery.importState == .ready)
        #expect(recovery.stagingToken == nil)
        #expect(try fixture.repository.podcasts().map(\.id) == [recovery.id])
    }

    @Test func staleStagingForRecoveryRecordIsProtectedFromCleanup() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let staged = try fixture.store.stageMP4(
            from: fixture.source(named: "protected.mp4", contents: "protected")
        )
        let recovery = PodcastRecord(
            contentSHA256: "digest-that-does-not-match-yet",
            title: "Protégé",
            originalFilename: "protected.mp4",
            relativeFilePath: "",
            importState: .recoveryRequired,
            stagingToken: staged.token
        )
        try fixture.repository.add(recovery)
        let stagingDirectory = fixture.support
            .appendingPathComponent("Podcasts/.staging")
            .appendingPathComponent(staged.token.uuidString)
        let oldDate = Date(timeIntervalSince1970: 1)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: stagingDirectory.path)

        let report = try fixture.service.reconcileImports(now: oldDate.addingTimeInterval(8 * 24 * 60 * 60))

        #expect(report.missingPodcastIDs.contains(recovery.id))
        #expect(!report.removedStagingTokens.contains(staged.token))
        #expect(FileManager.default.fileExists(atPath: stagingDirectory.path))
    }

    @Test func pendingAndRecoveryImportsStayHiddenFromTheLibrary() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let pending = PodcastRecord(
            title: "En attente",
            originalFilename: "pending.mp4",
            relativeFilePath: "",
            importState: .pending,
            stagingToken: UUID()
        )
        let recovery = PodcastRecord(
            title: "À récupérer",
            originalFilename: "recovery.mp4",
            relativeFilePath: "",
            importState: .recoveryRequired
        )
        try fixture.repository.add(pending)
        try fixture.repository.add(recovery)

        #expect(try fixture.repository.podcasts().isEmpty)
    }

    private enum TestSaveError: Error {
        case failed
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let sourceRoot: URL
        let support: URL
        let container: ModelContainer
        let repository: PodcastRepository
        let store: PodcastFileStore
        let validator: CountingValidator
        let service: PodcastImportService

        init(save: ((ModelContext) throws -> Void)? = nil) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            sourceRoot = root.appendingPathComponent("Source")
            support = root.appendingPathComponent("Support")
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            container = try ModelContainer(
                for: PodcastRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            repository = PodcastRepository(context: container.mainContext, save: save)
            store = try PodcastFileStore(applicationSupportURL: support)
            validator = CountingValidator()
            service = PodcastImportService(repository: repository, fileStore: store, validator: validator)
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

    @MainActor
    private final class CountingValidator: PodcastImportValidating {
        private(set) var validationCount = 0

        func validateMP4(at _: URL) async throws -> Double? {
            validationCount += 1
            return 42
        }
    }
}
