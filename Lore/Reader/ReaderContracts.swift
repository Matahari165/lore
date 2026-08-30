import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

/// Boundary implemented by the local data layer. Locator data is kept opaque so
/// the persistence model does not depend on Readium's internal fields.
@MainActor
protocol ReaderProgressStore: AnyObject {
    func storedLocator(for bookID: UUID) throws -> StoredLocator?
    func saveLocator(_ stored: StoredLocator, progression: Double?, for bookID: UUID) throws
}

struct StoredLocator: Sendable, Equatable {
    let data: Data
    let schemaVersion: Int?
}

enum ReaderLifecycleState: Sendable {
    case active
    case inactive
    case background
}

@MainActor
protocol ReaderLocationProviding: AnyObject {
    var currentLocation: Locator? { get }
    var viewController: UIViewController { get }
}

@MainActor
protocol EPUBReaderControlling: ReaderLocationProviding {
    func submitPreferences(_ preferences: EPUBPreferences)
    func go(to link: Link, options: NavigatorGoOptions) async -> Bool
}

struct ReaderChapter: Identifiable, Sendable {
    let id: String
    let title: String
    let depth: Int
    let link: Link

    static func flatten(_ links: [Link], depth: Int = 0, path: String = "") -> [ReaderChapter] {
        links.enumerated().flatMap { index, link in
            let itemPath = path.isEmpty ? "\(index)" : "\(path).\(index)"
            let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let chapter = ReaderChapter(
                id: "\(itemPath):\(link.href)",
                title: title?.isEmpty == false ? title! : "Chapitre sans titre",
                depth: depth,
                link: link
            )
            return [chapter] + flatten(link.children, depth: depth + 1, path: itemPath)
        }
    }
}

@MainActor
protocol ReadingPositionManaging: AnyObject {
    func record(_ locator: Locator)
    func flush(currentLocator: Locator?) async throws
}

struct RestoredReaderLocation {
    let locator: Locator?
    let requiresRewrite: Bool
}

enum ReaderLocationRestorer {
    @MainActor
    static func restore(bookID: UUID, from store: any ReaderProgressStore) throws -> RestoredReaderLocation {
        guard let stored = try store.storedLocator(for: bookID) else {
            return RestoredReaderLocation(locator: nil, requiresRewrite: false)
        }
        let decoded = try LocatorPersistenceCodec.decode(stored)
        return RestoredReaderLocation(locator: decoded.locator, requiresRewrite: decoded.requiresRewrite)
    }
}

enum LocatorPersistenceCodec {
    static let currentSchemaVersion = 1

    struct Decoded {
        let locator: Locator
        let requiresRewrite: Bool
    }

    static func encode(_ locator: Locator) throws -> StoredLocator {
        StoredLocator(data: try locator.jsonData(), schemaVersion: currentSchemaVersion)
    }

    static func decode(_ stored: StoredLocator) throws -> Decoded {
        guard stored.schemaVersion == nil || stored.schemaVersion == currentSchemaVersion else {
            throw ReaderError.unsupportedLocatorSchemaVersion
        }
        do {
            return Decoded(
                locator: try Locator(jsonData: stored.data),
                requiresRewrite: stored.schemaVersion == nil
            )
        } catch {
            throw ReaderError.invalidSavedLocation
        }
    }
}
