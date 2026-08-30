import Foundation
import SwiftData
import Testing
@testable import Lore

@MainActor
struct BookImportServiceTests {
    @Test func duplicateBytesReturnExistingBookAndImportsAreSerialized() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let firstURL = try fixture.source(named: "first.epub", contents: "identical")
        let secondURL = try fixture.source(named: "second.epub", contents: "identical")

        async let firstID: UUID = { @MainActor in
            try await fixture.service.importEPUB(from: firstURL).book.id
        }()
        async let secondID: UUID = { @MainActor in
            try await fixture.service.importEPUB(from: secondURL).book.id
        }()
        let ids = try await [firstID, secondID]

        #expect(ids[0] == ids[1])
        #expect(try fixture.repository.books().count == 1)
        #expect(fixture.validator.maximumConcurrentValidations == 1)
        #expect(fixture.validator.validatedURLs.count == 1)
        #expect(fixture.validator.validatedURLs[0].path.contains("/Books/.staging/"))
    }

    @Test func invalidEPUBLeavesNeitherRecordNorStaging() async throws {
        let fixture = try Fixture(validationError: FakeValidator.Failure.invalid)
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "invalid.epub", contents: "invalid")

        await #expect(throws: FakeValidator.Failure.self) {
            _ = try await fixture.service.importEPUB(from: source)
        }

        #expect(try fixture.repository.books().isEmpty)
        let staging = fixture.support.appendingPathComponent("Books/.staging")
        let contents = try FileManager.default.contentsOfDirectory(atPath: staging.path)
        #expect(contents.isEmpty)
    }

    @Test func missingMetadataUsesFilenameAndImportsSuccessfully() async throws {
        let fixture = try Fixture(metadata: ImportedEPUBMetadata(
            mediaType: "application/epub+zip", title: nil, author: nil, coverData: nil
        ))
        defer { fixture.cleanup() }
        let result = try await fixture.service.importEPUB(
            from: fixture.source(named: "Sans métadonnées.epub", contents: "valid")
        )
        #expect(result.book.title == "Sans métadonnées")
        #expect(result.book.author == nil)
    }

    @Test func reconciliationPromotesReferencedStagingAndKeepsMissingRecord() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let staged = try fixture.fileStore.stageEPUB(
            from: fixture.source(named: "pending.epub", contents: "pending")
        )
        let pending = BookRecord(
            contentSHA256: staged.contentSHA256, title: "Pending", relativeFilePath: "",
            importState: .pending, stagingToken: staged.token
        )
        let missing = BookRecord(
            contentSHA256: String(repeating: "a", count: 64), title: "Missing",
            relativeFilePath: "Books/missing/book.epub"
        )
        try fixture.repository.add(pending)
        try fixture.repository.add(missing)

        let report = try fixture.service.reconcileImports()

        #expect(report.recoveredBookIDs == [pending.id])
        #expect(try fixture.repository.book(id: pending.id)?.importState == .ready)
        #expect(try fixture.repository.book(id: missing.id) != nil)
        #expect(report.files.missingBookIDs.contains(missing.id))
    }

    @Test func immediateDuplicateRetryRecoversPendingStagingBeforeReturningBook() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let source = try fixture.source(named: "retry.epub", contents: "retry-staging")
        let staged = try fixture.fileStore.stageEPUB(from: source)
        let pending = BookRecord(
            contentSHA256: staged.contentSHA256, title: "Pending", relativeFilePath: "",
            importState: .pending, stagingToken: staged.token
        )
        try fixture.repository.add(pending)

        let result = try await fixture.service.importEPUB(from: source)

        #expect(result.book.id == pending.id)
        #expect(pending.importState == .ready)
        #expect(try fixture.fileStore.fileURL(for: pending.relativeFilePath).lastPathComponent == "book.epub")
        #expect(fixture.validator.validatedURLs.isEmpty)
    }

    @Test func immediateDuplicateRetryConfirmsFinalFileLeftByCrashWindow() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let source = try fixture.source(named: "retry-final.epub", contents: "retry-final")
        let staged = try fixture.fileStore.stageEPUB(from: source)
        let pending = BookRecord(
            contentSHA256: staged.contentSHA256, title: "Pending", relativeFilePath: "",
            importState: .pending, stagingToken: staged.token
        )
        try fixture.repository.add(pending)
        _ = try fixture.fileStore.promote(staged, to: pending.id)

        let result = try await fixture.service.importEPUB(from: source)

        #expect(result.book.id == pending.id)
        #expect(pending.importState == .ready)
        #expect(pending.relativeFilePath == fixture.fileStore.relativePath(forBookID: pending.id))
    }

    @MainActor
    private final class Fixture {
        let root: URL, sourceRoot: URL, support: URL
        let container: ModelContainer
        let repository: BookRepository
        let fileStore: BookFileStore
        let validator: FakeValidator
        let service: BookImportService

        init(metadata: ImportedEPUBMetadata = .init(
            mediaType: "application/epub+zip", title: "Title", author: "Author", coverData: nil
        ), validationError: Error? = nil) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            sourceRoot = root.appendingPathComponent("Source")
            support = root.appendingPathComponent("Support")
            try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            container = try ModelContainer(
                for: BookRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            repository = BookRepository(context: container.mainContext)
            fileStore = try BookFileStore(applicationSupportURL: support)
            validator = FakeValidator(metadata: metadata, error: validationError)
            service = BookImportService(repository: repository, fileStore: fileStore, publicationService: validator)
        }

        func source(named name: String, contents: String) throws -> URL {
            let url = sourceRoot.appendingPathComponent(name)
            try Data(contents.utf8).write(to: url)
            return url
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
}

@MainActor
private final class FakeValidator: EPUBImportValidating {
    enum Failure: Error { case invalid }
    let metadata: ImportedEPUBMetadata
    let error: Error?
    private(set) var validatedURLs: [URL] = []
    private var activeValidations = 0
    private(set) var maximumConcurrentValidations = 0

    init(metadata: ImportedEPUBMetadata, error: Error?) {
        self.metadata = metadata
        self.error = error
    }

    func validateEPUBForImport(at fileURL: URL) async throws -> ImportedEPUBMetadata {
        activeValidations += 1
        maximumConcurrentValidations = max(maximumConcurrentValidations, activeValidations)
        defer { activeValidations -= 1 }
        validatedURLs.append(fileURL)
        await Task.yield()
        if let error { throw error }
        return metadata
    }
}
