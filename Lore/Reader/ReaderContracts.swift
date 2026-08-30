import Foundation
import ReadiumShared

/// Boundary implemented by the local data layer. Locator data is kept opaque so
/// the persistence model does not depend on Readium's internal fields.
@MainActor
protocol ReaderProgressStore: AnyObject {
    func locatorData(for bookID: UUID) throws -> Data?
    func saveLocatorData(_ data: Data, progression: Double?, for bookID: UUID) throws
}

enum ReaderLifecycleState: Sendable {
    case active
    case inactive
    case background
}

enum LocatorJSONCodec {
    static func encode(_ locator: Locator) throws -> Data {
        try locator.jsonData()
    }

    static func decode(_ data: Data) throws -> Locator {
        do {
            return try Locator(jsonData: data)
        } catch {
            throw ReaderError.invalidSavedLocation
        }
    }
}
