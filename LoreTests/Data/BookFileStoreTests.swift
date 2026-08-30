import Foundation
import Testing
@testable import Lore

struct BookFileStoreTests {
    @Test func stagesHashesAndPromotesTheExactPrivateCopy() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let source = try fixture.sourceFile(named: "sample.epub", contents: "epub")
        let staged = try fixture.store.stageEPUB(from: source)
        try Data("changed".utf8).write(to: source)
        let bookID = UUID()
        let path = try fixture.store.promote(staged, to: bookID)
        #expect(path == "Books/\(bookID.uuidString)/book.epub")
        #expect(try Data(contentsOf: fixture.store.fileURL(for: path)) == Data("epub".utf8))
        #expect(staged.contentSHA256 == "83e895b8f0af41ca0905b4e89c6979eab60b36a62bdb8efc4730dfd446aded7f")
    }

    @Test func identicalBytesHaveTheSameDigestDespiteDifferentNames() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let first = try fixture.store.stageEPUB(from: fixture.sourceFile(named: "one.epub", contents: "same"))
        let second = try fixture.store.stageEPUB(from: fixture.sourceFile(named: "two.epub", contents: "same"))
        #expect(first.contentSHA256 == second.contentSHA256)
    }

    @Test func rejectsNonEPUBWithoutCreatingStaging() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let source = try fixture.sourceFile(named: "sample.zip", contents: "zip")
        #expect(throws: BookFileStoreError.unsupportedFileType) { try fixture.store.stageEPUB(from: source) }
    }

    @Test func reconciliationRemovesOldStagingAndKeepsOrphanFinal() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let old = try fixture.store.stageEPUB(from: fixture.sourceFile(named: "old.epub", contents: "old"))
        let recent = try fixture.store.stageEPUB(from: fixture.sourceFile(named: "recent.epub", contents: "recent"))
        let orphanID = UUID()
        let orphan = try fixture.store.stageEPUB(from: fixture.sourceFile(named: "orphan.epub", contents: "orphan"))
        _ = try fixture.store.promote(orphan, to: orphanID)
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-100)],
            ofItemAtPath: old.fileURL.deletingLastPathComponent().path
        )
        let report = try fixture.store.reconcile(
            referencedBookIDs: [], referencedStagingTokens: [recent.token], now: now, staleAfter: 10
        )
        #expect(report.removedStagingTokens == [old.token])
        #expect(report.orphanBookIDs == [orphanID])
        #expect(FileManager.default.fileExists(atPath: recent.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.support.appendingPathComponent("Books/\(orphanID.uuidString)/book.epub").path))
    }

    @Test func missingRecordFileIsReportedNotDeleted() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let missingID = UUID()
        let report = try fixture.store.reconcile(referencedBookIDs: [missingID], referencedStagingTokens: [])
        #expect(report.missingBookIDs == [missingID])
    }

    @Test func rejectsAPathEscapingApplicationSupport() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        #expect(throws: BookFileStoreError.storedFileMissing) {
            try fixture.store.fileURL(for: "Books/../outside.epub")
        }
    }

    struct Fixture {
        let root: URL, source: URL, support: URL, store: BookFileStore
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            source = root.appendingPathComponent("Source")
            support = root.appendingPathComponent("Support")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            store = try BookFileStore(applicationSupportURL: support)
        }
        func sourceFile(named name: String, contents: String) throws -> URL {
            let url = source.appendingPathComponent(name)
            try Data(contents.utf8).write(to: url)
            return url
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
}
