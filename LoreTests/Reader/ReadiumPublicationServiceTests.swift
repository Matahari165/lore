import Foundation
import Testing
@testable import Lore

struct ReadiumPublicationServiceTests {
    @Test func cacheKeyMatchesOnlyTheSameOnDiskRevision() {
        let date = Date(timeIntervalSince1970: 1234)
        let key = ReadiumPublicationCacheKey(
            standardizedPath: "/books/lore.epub",
            fileSize: 42,
            modificationDate: date
        )

        #expect(key == ReadiumPublicationCacheKey(
            standardizedPath: "/books/lore.epub",
            fileSize: 42,
            modificationDate: date
        ))
        #expect(key != ReadiumPublicationCacheKey(
            standardizedPath: "/books/lore.epub",
            fileSize: 43,
            modificationDate: date
        ))
        #expect(key != ReadiumPublicationCacheKey(
            standardizedPath: "/books/lore.epub",
            fileSize: 42,
            modificationDate: date.addingTimeInterval(1)
        ))
        #expect(key != ReadiumPublicationCacheKey(
            standardizedPath: "/other/lore.epub",
            fileSize: 42,
            modificationDate: date
        ))
    }
}
