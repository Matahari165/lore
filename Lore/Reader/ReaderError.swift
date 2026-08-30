import Foundation

enum ReaderError: LocalizedError {
    case invalidFileURL
    case unsupportedPublication
    case restrictedPublication
    case invalidSavedLocation
    case unsupportedLocatorSchemaVersion
    case openingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidFileURL:
            "Le fichier du livre est introuvable."
        case .unsupportedPublication:
            "Ce fichier n’est pas un EPUB compatible."
        case .restrictedPublication:
            "Cet EPUB est protégé et ne peut pas être ouvert dans Lore."
        case .invalidSavedLocation:
            "La dernière position de lecture est illisible."
        case .unsupportedLocatorSchemaVersion:
            "La position de lecture provient d’une version plus récente de Lore."
        case .openingFailed:
            "Le livre n’a pas pu être ouvert."
        }
    }
}
