import Foundation
import ReadiumShared

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
