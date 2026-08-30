import Foundation

enum LoreError: LocalizedError, Equatable {
    case accessDenied
    case copyFailed
    case invalidEPUB
    case protectedEPUB
    case missingBook
    case unreadablePosition
    case readerUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Lore ne peut pas accéder à ce fichier. Choisissez-le à nouveau dans Fichiers."
        case .copyFailed:
            "Le livre n’a pas pu être copié dans Lore. Vérifiez l’espace disponible puis réessayez."
        case .invalidEPUB:
            "Ce fichier n’est pas un EPUB lisible."
        case .protectedEPUB:
            "Les EPUB protégés par DRM ne sont pas pris en charge."
        case .missingBook:
            "Le fichier de ce livre est introuvable. Importez-le à nouveau."
        case .unreadablePosition:
            "La dernière position est illisible. Le livre sera ouvert au début."
        case .readerUnavailable:
            "Le lecteur n’a pas pu ouvrir ce livre."
        }
    }
}
