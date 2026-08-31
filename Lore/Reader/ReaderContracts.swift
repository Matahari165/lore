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

enum HighlightColor: String, Sendable, CaseIterable {
    case yellow

    var uiColor: UIColor { UIColor(red: 0.96, green: 0.72, blue: 0.20, alpha: 0.48) }
}

struct ReaderHighlight: Identifiable, Sendable {
    let id: UUID
    let bookID: UUID
    let locator: Locator
    let text: String
    let createdAt: Date
    let color: HighlightColor
}

@MainActor
protocol HighlightStoring: AnyObject {
    func highlights(for bookID: UUID) throws -> [ReaderHighlight]
    func addHighlight(bookID: UUID, locator: Locator, text: String, color: HighlightColor) throws -> ReaderHighlight
    func deleteHighlight(id: UUID, bookID: UUID) throws
}

struct StoredHighlightLocator: Sendable, Equatable {
    let data: Data
    let schemaVersion: Int
}

enum HighlightLocatorCodec {
    static let currentSchemaVersion = 1

    static func encode(_ locator: Locator) throws -> StoredHighlightLocator {
        StoredHighlightLocator(data: try locator.jsonData(), schemaVersion: currentSchemaVersion)
    }

    static func decode(_ stored: StoredHighlightLocator) throws -> Locator {
        guard stored.schemaVersion == currentSchemaVersion else {
            throw HighlightStoreError.unsupportedLocatorSchemaVersion
        }
        do {
            return try Locator(jsonData: stored.data)
        } catch {
            throw HighlightStoreError.invalidLocator
        }
    }
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
    func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool
    func go(to link: Link, options: NavigatorGoOptions) async -> Bool
}

enum ReaderTapZone: Equatable {
    case backward, chrome, forward

    static func resolve(x: CGFloat, width: CGFloat, isRTL: Bool) -> ReaderTapZone {
        guard width > 0 else { return .chrome }
        let fraction = min(max(x / width, 0), 1)
        if fraction < 1 / 3 { return isRTL ? .forward : .backward }
        if fraction > 2 / 3 { return isRTL ? .backward : .forward }
        return .chrome
    }
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
