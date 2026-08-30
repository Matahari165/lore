import Foundation
import Testing
@testable import Lore

struct BookFileStoreTests {
    @Test func importsToStableRelativePath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let bookID = UUID()
        let source = fixture.source.appendingPathComponent("sample.epub")
        try Data("epub".utf8).write(to: source)

        let path = try fixture.store.importEPUB(from: source, bookID: bookID)

        #expect(path == "Books/\(bookID.uuidString)/book.epub")
        #expect(try Data(contentsOf: fixture.store.fileURL(for: path)) == Data("epub".utf8))
    }

    @Test func rejectsNonEPUBWithoutCreatingBookDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = fixture.source.appendingPathComponent("sample.zip")
        try Data().write(to: source)

        #expect(throws: BookFileStoreError.unsupportedFileType) {
            try fixture.store.importEPUB(from: source, bookID: UUID())
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.support.appendingPathComponent("Books").path))
    }

    @Test func missingStoredFileIsReported() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        #expect(throws: BookFileStoreError.storedFileMissing) {
            try fixture.store.fileURL(for: "Books/missing/book.epub")
        }
    }

    @Test func rejectsAPathEscapingApplicationSupport() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        #expect(throws: BookFileStoreError.storedFileMissing) {
            try fixture.store.fileURL(for: "Books/../outside.epub")
        }
    }

    private struct Fixture {
        let root: URL
        let source: URL
        let support: URL
        let store: BookFileStore

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            source = root.appendingPathComponent("Source")
            support = root.appendingPathComponent("Support")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            store = try BookFileStore(applicationSupportURL: support)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
