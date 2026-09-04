import Foundation
import Testing
@testable import Lore

struct EPUBImportSourceResolverTests {
    @Test func recursivelyFindsOnlyVisibleRegularEPUBFilesInStableOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("B.EPUB"))
        try Data().write(to: nested.appendingPathComponent("a.epub"))
        try Data().write(to: root.appendingPathComponent("notes.txt"))
        try Data().write(to: root.appendingPathComponent(".hidden.epub"))

        let names = try EPUBImportSourceResolver.epubURLs(from: root).map(\.lastPathComponent)

        #expect(names == ["B.EPUB", "a.epub"])
    }

    @Test func rejectsNonEPUBFileInsteadOfBroadDataFallback() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)

        #expect(throws: BookFileStoreError.unsupportedFileType) {
            _ = try EPUBImportSourceResolver.epubURLs(from: url)
        }
    }

    @Test func rejectsFolderBeyondExplicitEPUBLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("one.epub"))
        try Data().write(to: root.appendingPathComponent("two.epub"))

        #expect(throws: EPUBImportSourceResolverError.tooManyFiles(limit: 1)) {
            _ = try EPUBImportSourceResolver.epubURLs(from: root, maximumFileCount: 1)
        }
    }

    @Test func applicationInfoDeclaresEPUBDocumentType() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Lore-Info.plist")
        let data = try Data(contentsOf: sourceURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
        let documents = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let identifiers = documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        #expect(identifiers.contains("org.idpf.epub-container"))
    }
}
