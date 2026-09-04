import CryptoKit
import Foundation
import SwiftData

/// Format portable et versionne des donnees personnelles de Lore.
/// Les conversations IA sont volontairement absentes de ce contrat.
struct LoreBackupPayload: Codable, Sendable, Equatable {
    static let currentVersion = 1

    let formatVersion: Int
    let createdAt: Date
    let books: [Book]
    let sessions: [Session]
    let highlights: [Highlight]
    let vocabulary: [Vocabulary]
    let podcasts: [Podcast]
    let collections: [Collection]
    let collectionMemberships: [CollectionMembership]

    struct Book: Codable, Sendable, Equatable {
        let id: UUID
        let contentSHA256: String?
        let title: String
        let author: String?
        let coverData: Data?
        let mediaType: String
        let importedAt: Date
        let lastLocatorJSON: Data?
        let lastProgression: Double?
        let progressUpdatedAt: Date?
        let locatorSchemaVersion: Int?
        let finishedAt: Date?
        let rating: Int?
        let readingYear: Int?
        let isHiddenFromResume: Bool
    }

    struct Session: Codable, Sendable, Equatable {
        let id: UUID
        let bookID: UUID
        let startedAt: Date
        let lastActivityAt: Date
        let endedAt: Date?
    }

    struct Highlight: Codable, Sendable, Equatable {
        let id: UUID
        let bookID: UUID
        let locatorJSON: Data
        let locatorSchemaVersion: Int
        let text: String
        let createdAt: Date
        let colorRawValue: String
        let note: String?
    }

    struct Vocabulary: Codable, Sendable, Equatable {
        let id: UUID
        let bookID: UUID
        let locatorJSON: Data
        let locatorSchemaVersion: Int
        let text: String
        let createdAt: Date
    }

    struct Podcast: Codable, Sendable, Equatable {
        let id: UUID
        let contentSHA256: String?
        let title: String
        let originalFilename: String
        let importedAt: Date
        let durationSeconds: Double?
        let lastPositionSeconds: Double
        let progressUpdatedAt: Date?
    }

    struct Collection: Codable, Sendable, Equatable {
        let id: UUID
        let name: String
        let normalizedName: String
        let createdAt: Date
    }

    struct CollectionMembership: Codable, Sendable, Equatable {
        let id: UUID
        let collectionID: UUID
        let bookID: UUID
        let addedAt: Date
    }
}

struct LoreBackupManifest: Codable, Sendable, Equatable {
    let formatVersion: Int
    let createdAt: Date
    let payloadSHA256: String
    let epubSHA256ByBookID: [UUID: String]
    let recordCounts: [String: Int]
    let missingEPUBBookIDs: [UUID]
    let podcastSHA256ByPodcastID: [UUID: String]
    let missingPodcastIDs: [UUID]
}

struct LoreRestoreReport: Sendable, Equatable {
    var insertedBooks = 0
    var mergedBooks = 0
    var insertedSessions = 0
    var insertedHighlights = 0
    var insertedVocabulary = 0
    var insertedPodcasts = 0
    var insertedCollections = 0
    var insertedCollectionMemberships = 0
    var restoredEPUBs = 0
    var restoredPodcasts = 0
}

enum LoreBackupError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidPayloadDigest
    case invalidEPUBDigest(UUID)
    case invalidReference(UUID)
    case invalidProgression(UUID)
    case duplicateIdentifier(String, UUID)
    case duplicateContentDigest(String)
    case invalidRating(UUID)
    case invalidReadingYear(UUID)
    case invalidLocator(UUID)
    case orphanEPUBDigest(UUID)
    case conflictingBook(UUID)
    case conflictingLocalContent(String)
    case conflictingRecord(String, UUID)
    case invalidRequiredFields(UUID)
    case invalidContentDigest(UUID)
    case invalidColor(UUID)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version): "La sauvegarde Lore utilise une version non prise en charge (\(version))."
        case .invalidPayloadDigest: "Les donnees de la sauvegarde ont ete modifiees ou endommagees."
        case let .invalidEPUBDigest(id): "L'EPUB du livre \(id) ne correspond pas a la sauvegarde."
        case let .invalidReference(id): "Une donnee de la sauvegarde reference un livre absent (\(id))."
        case let .invalidProgression(id): "La progression du livre \(id) est invalide."
        case let .duplicateIdentifier(type, id): "La sauvegarde contient deux \(type) avec l'identifiant \(id)."
        case let .duplicateContentDigest(digest): "Deux livres de la sauvegarde revendiquent le meme contenu \(digest)."
        case let .invalidRating(id): "La note du livre \(id) est invalide."
        case let .invalidReadingYear(id): "L'annee de lecture du livre \(id) est invalide."
        case let .invalidLocator(id): "Le Locator de l'element \(id) est invalide."
        case let .orphanEPUBDigest(id): "Le manifeste reference un EPUB sans livre correspondant (\(id))."
        case let .conflictingBook(id): "Le livre \(id) existe deja avec un contenu different. Aucune donnee n'a ete remplacee."
        case let .conflictingLocalContent(digest): "Un autre livre local utilise deja le contenu \(digest). Aucune donnee n'a ete remplacee."
        case let .conflictingRecord(type, id): "Le \(type) \(id) existe deja avec un contenu different. Aucune donnee n'a ete remplacee."
        case let .invalidRequiredFields(id): "Le livre \(id) ne contient pas tous les champs requis."
        case let .invalidContentDigest(id): "L'empreinte de contenu du livre \(id) est invalide."
        case let .invalidColor(id): "La couleur du surlignage \(id) est invalide."
        }
    }
}

@MainActor
final class LoreBackupService {
    static let manifestFileName = "manifest.json"
    static let payloadFileName = "lore-data.json"
    static let epubDirectoryName = "EPUB"
    static let podcastDirectoryName = "Podcasts"

    private let context: ModelContext
    private let fileStore: BookFileStore
    private let podcastFileStore: PodcastFileStore
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(context: ModelContext, fileStore: BookFileStore, podcastFileStore: PodcastFileStore, fileManager: FileManager = .default) {
        self.context = context
        self.fileStore = fileStore
        self.podcastFileStore = podcastFileStore
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func snapshot(at date: Date = .now) throws -> LoreBackupPayload {
        LoreBackupPayload(
            formatVersion: LoreBackupPayload.currentVersion,
            createdAt: date,
            books: try context.fetch(FetchDescriptor<BookRecord>()).map(Self.backupBook),
            sessions: try context.fetch(FetchDescriptor<ReadingSessionRecord>()).map {
                .init(id: $0.id, bookID: $0.bookID, startedAt: $0.startedAt, lastActivityAt: $0.lastActivityAt, endedAt: $0.endedAt)
            },
            highlights: try context.fetch(FetchDescriptor<HighlightRecord>()).map {
                .init(id: $0.id, bookID: $0.bookID, locatorJSON: $0.locatorJSON, locatorSchemaVersion: $0.locatorSchemaVersion, text: $0.text, createdAt: $0.createdAt, colorRawValue: $0.colorRawValue, note: $0.note)
            },
            vocabulary: try context.fetch(FetchDescriptor<VocabularyRecord>()).map {
                .init(id: $0.id, bookID: $0.bookID, locatorJSON: $0.locatorJSON, locatorSchemaVersion: $0.locatorSchemaVersion, text: $0.text, createdAt: $0.createdAt)
            },
            podcasts: try context.fetch(FetchDescriptor<PodcastRecord>()).map {
                .init(id: $0.id, contentSHA256: $0.contentSHA256, title: $0.title, originalFilename: $0.originalFilename, importedAt: $0.importedAt, durationSeconds: $0.durationSeconds, lastPositionSeconds: $0.lastPositionSeconds, progressUpdatedAt: $0.progressUpdatedAt)
            },
            collections: try context.fetch(FetchDescriptor<ManualCollectionRecord>()).map {
                .init(id: $0.id, name: $0.name, normalizedName: $0.normalizedName, createdAt: $0.createdAt)
            },
            collectionMemberships: try context.fetch(FetchDescriptor<CollectionMembershipRecord>()).map {
                .init(id: $0.id, collectionID: $0.collectionID, bookID: $0.bookID, addedAt: $0.addedAt)
            }
        )
    }

    /// Cree un paquet repertoire. Il peut etre compresse ou copie par Fichiers sans
    /// melanger les EPUB aux donnees structurees.
    func exportBackup(to packageURL: URL, at date: Date = .now) throws {
        guard !fileManager.fileExists(atPath: packageURL.path) else { throw CocoaError(.fileWriteFileExists) }
        let temporary = packageURL.deletingLastPathComponent().appendingPathComponent(".LoreBackup-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: false)
            let payload = try snapshot(at: date)
            let payloadData = try encoder.encode(payload)
            try payloadData.write(to: temporary.appendingPathComponent(Self.payloadFileName), options: .atomic)

            let epubDirectory = temporary.appendingPathComponent(Self.epubDirectoryName, isDirectory: true)
            try fileManager.createDirectory(at: epubDirectory, withIntermediateDirectories: false)
            var epubDigests: [UUID: String] = [:]
            var missingEPUBBookIDs: [UUID] = []
            for book in payload.books {
                guard let expected = book.contentSHA256 else { missingEPUBBookIDs.append(book.id); continue }
                guard
                      let record = try fetchBook(id: book.id),
                      let source = try? fileStore.fileURL(for: record.relativeFilePath) else { missingEPUBBookIDs.append(book.id); continue }
                let destination = epubDirectory.appendingPathComponent("\(book.id.uuidString).epub")
                try fileManager.copyItem(at: source, to: destination)
                guard try fileStore.sha256(of: destination) == expected else { throw LoreBackupError.invalidEPUBDigest(book.id) }
                epubDigests[book.id] = expected
            }
            let podcastDirectory = temporary.appendingPathComponent(Self.podcastDirectoryName, isDirectory: true)
            try fileManager.createDirectory(at: podcastDirectory, withIntermediateDirectories: false)
            var podcastDigests: [UUID: String] = [:]
            var missingPodcastIDs: [UUID] = []
            let podcastRecords = try context.fetch(FetchDescriptor<PodcastRecord>())
            for podcast in payload.podcasts {
                guard let expected = podcast.contentSHA256,
                      let record = podcastRecords.first(where: { $0.id == podcast.id }),
                      let source = try? podcastFileStore.fileURL(for: record.relativeFilePath) else {
                    missingPodcastIDs.append(podcast.id); continue
                }
                let destination = podcastDirectory.appendingPathComponent("\(podcast.id.uuidString).mp4")
                try fileManager.copyItem(at: source, to: destination)
                guard try podcastFileStore.contentSHA256(of: destination) == expected else { throw LoreBackupError.invalidEPUBDigest(podcast.id) }
                podcastDigests[podcast.id] = expected
            }
            let manifest = LoreBackupManifest(
                formatVersion: LoreBackupPayload.currentVersion,
                createdAt: date,
                payloadSHA256: Self.sha256(of: payloadData),
                epubSHA256ByBookID: epubDigests,
                recordCounts: ["books": payload.books.count, "sessions": payload.sessions.count, "highlights": payload.highlights.count, "vocabulary": payload.vocabulary.count, "podcasts": payload.podcasts.count, "collections": payload.collections.count, "collectionMemberships": payload.collectionMemberships.count],
                missingEPUBBookIDs: missingEPUBBookIDs.sorted { $0.uuidString < $1.uuidString },
                podcastSHA256ByPodcastID: podcastDigests,
                missingPodcastIDs: missingPodcastIDs.sorted { $0.uuidString < $1.uuidString }
            )
            try encoder.encode(manifest).write(to: temporary.appendingPathComponent(Self.manifestFileName), options: .atomic)
            try fileManager.moveItem(at: temporary, to: packageURL)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    /// Valide le paquet entier avant de toucher SwiftData, puis fusionne sans
    /// suppression. Un EPUB local existant n'est jamais remplace.
    func restoreBackup(from packageURL: URL) throws -> LoreRestoreReport {
        let manifest = try decoder.decode(LoreBackupManifest.self, from: Data(contentsOf: packageURL.appendingPathComponent(Self.manifestFileName)))
        guard manifest.formatVersion == LoreBackupPayload.currentVersion else { throw LoreBackupError.unsupportedVersion(manifest.formatVersion) }
        let payloadData = try Data(contentsOf: packageURL.appendingPathComponent(Self.payloadFileName))
        guard Self.sha256(of: payloadData) == manifest.payloadSHA256 else { throw LoreBackupError.invalidPayloadDigest }
        let payload = try decoder.decode(LoreBackupPayload.self, from: payloadData)
        try validate(payload: payload, packageURL: packageURL, manifest: manifest)
        return try merge(payload: payload, packageURL: packageURL, epubDigests: manifest.epubSHA256ByBookID, podcastDigests: manifest.podcastSHA256ByPodcastID)
    }

    func merge(payload: LoreBackupPayload, packageURL: URL? = nil, epubDigests: [UUID: String] = [:], podcastDigests: [UUID: String] = [:]) throws -> LoreRestoreReport {
        try validatePayload(payload)
        let localBooks = try context.fetch(FetchDescriptor<BookRecord>())
        let localByID = Dictionary(uniqueKeysWithValues: localBooks.map { ($0.id, $0) })
        for book in payload.books {
            if let local = localByID[book.id], Self.backupBook(local) != book {
                throw LoreBackupError.conflictingBook(book.id)
            }
            if let digest = book.contentSHA256,
               localBooks.contains(where: { $0.contentSHA256 == digest && $0.id != book.id }) {
                throw LoreBackupError.conflictingLocalContent(digest)
            }
        }
        try validateExistingChildren(payload)
        let localPodcasts = try context.fetch(FetchDescriptor<PodcastRecord>())
        for podcast in payload.podcasts {
            if let local = localPodcasts.first(where: { $0.id == podcast.id }), Self.backupPodcast(local) != podcast {
                throw LoreBackupError.conflictingRecord("podcast", podcast.id)
            }
            if let digest = podcast.contentSHA256,
               localPodcasts.contains(where: { $0.contentSHA256 == digest && $0.id != podcast.id }) {
                throw LoreBackupError.conflictingLocalContent(digest)
            }
        }

        // Tous les fichiers récupérables sont copiés et vérifiés avant la
        // première mutation SwiftData. En cas d'échec, aucun livre n'est créé.
        var stagedEPUBs: [UUID: StagedBookFile] = [:]
        var stagedPodcasts: [UUID: StagedPodcastFile] = [:]
        if let packageURL {
            do {
                for (bookID, digest) in epubDigests {
                    if let local = localByID[bookID], let localURL = try? fileStore.fileURL(for: local.relativeFilePath) {
                        guard try fileStore.sha256(of: localURL) == digest else {
                            throw LoreBackupError.invalidEPUBDigest(bookID)
                        }
                        continue
                    }
                    // Reprise du cas où le déplacement final a réussi mais où
                    // la sauvegarde SwiftData suivante a été interrompue.
                    if (try? fileStore.finalFile(bookID: bookID, expectedSHA256: digest)) != nil { continue }
                    let source = packageURL.appendingPathComponent(Self.epubDirectoryName).appendingPathComponent("\(bookID.uuidString).epub")
                    let staged = try fileStore.stageEPUB(from: source)
                    guard staged.contentSHA256 == digest else {
                        fileStore.discard(staged)
                        throw LoreBackupError.invalidEPUBDigest(bookID)
                    }
                    stagedEPUBs[bookID] = staged
                }
                for (podcastID, digest) in podcastDigests {
                    if let local = localPodcasts.first(where: { $0.id == podcastID }),
                       let localURL = try? podcastFileStore.fileURL(for: local.relativeFilePath) {
                        guard try podcastFileStore.contentSHA256(of: localURL) == digest else { throw LoreBackupError.invalidEPUBDigest(podcastID) }
                        continue
                    }
                    if (try? podcastFileStore.finalFile(podcastID: podcastID, expectedSHA256: digest)) != nil { continue }
                    let source = packageURL.appendingPathComponent(Self.podcastDirectoryName).appendingPathComponent("\(podcastID.uuidString).mp4")
                    let staged = try podcastFileStore.stageMP4(from: source)
                    guard staged.contentSHA256 == digest else {
                        podcastFileStore.discard(staged)
                        throw LoreBackupError.invalidEPUBDigest(podcastID)
                    }
                    stagedPodcasts[podcastID] = staged
                }
            } catch {
                stagedEPUBs.values.forEach(fileStore.discard)
                stagedPodcasts.values.forEach(podcastFileStore.discard)
                throw error
            }
        }

        var report = LoreRestoreReport()
        for book in payload.books {
            if let existing = try fetchBook(id: book.id) {
                if stagedEPUBs[book.id] != nil { existing.importState = .recoveryRequired }
                report.mergedBooks += 1
            } else {
                context.insert(Self.record(from: book, relativeFilePath: ""))
                report.insertedBooks += 1
            }
        }
        try insertMissing(payload.sessions, existing: Set(try context.fetch(FetchDescriptor<ReadingSessionRecord>()).map(\.id)), id: \.id) { item in
            context.insert(ReadingSessionRecord(id: item.id, bookID: item.bookID, startedAt: item.startedAt, lastActivityAt: item.lastActivityAt, endedAt: item.endedAt)); report.insertedSessions += 1
        }
        try insertMissing(payload.highlights, existing: Set(try context.fetch(FetchDescriptor<HighlightRecord>()).map(\.id)), id: \.id) { item in
            context.insert(HighlightRecord(id: item.id, bookID: item.bookID, locatorJSON: item.locatorJSON, locatorSchemaVersion: item.locatorSchemaVersion, text: item.text, createdAt: item.createdAt, colorRawValue: item.colorRawValue, note: item.note)); report.insertedHighlights += 1
        }
        try insertMissing(payload.vocabulary, existing: Set(try context.fetch(FetchDescriptor<VocabularyRecord>()).map(\.id)), id: \.id) { item in
            context.insert(VocabularyRecord(id: item.id, bookID: item.bookID, locatorJSON: item.locatorJSON, locatorSchemaVersion: item.locatorSchemaVersion, text: item.text, createdAt: item.createdAt)); report.insertedVocabulary += 1
        }
        try insertMissing(payload.podcasts, existing: Set(localPodcasts.map(\.id)), id: \.id) { item in
            context.insert(PodcastRecord(id: item.id, contentSHA256: item.contentSHA256, title: item.title, originalFilename: item.originalFilename, relativeFilePath: "", importedAt: item.importedAt, durationSeconds: item.durationSeconds, lastPositionSeconds: item.lastPositionSeconds, progressUpdatedAt: item.progressUpdatedAt, importState: .recoveryRequired)); report.insertedPodcasts += 1
        }
        try insertMissing(payload.collections, existing: Set(try context.fetch(FetchDescriptor<ManualCollectionRecord>()).map(\.id)), id: \.id) { item in
            context.insert(ManualCollectionRecord(id: item.id, name: item.name, normalizedName: item.normalizedName, createdAt: item.createdAt)); report.insertedCollections += 1
        }
        try insertMissing(payload.collectionMemberships, existing: Set(try context.fetch(FetchDescriptor<CollectionMembershipRecord>()).map(\.id)), id: \.id) { item in
            context.insert(CollectionMembershipRecord(id: item.id, collectionID: item.collectionID, bookID: item.bookID, addedAt: item.addedAt)); report.insertedCollectionMemberships += 1
        }
        do { try context.save() }
        catch {
            context.rollback()
            stagedEPUBs.values.forEach(fileStore.discard)
            stagedPodcasts.values.forEach(podcastFileStore.discard)
            throw error
        }
        for (podcastID, staged) in stagedPodcasts {
            guard let podcast = try context.fetch(FetchDescriptor<PodcastRecord>()).first(where: { $0.id == podcastID }) else { continue }
            podcast.relativeFilePath = try podcastFileStore.promote(staged, to: podcastID)
            podcast.importState = .ready
            try context.save()
            report.restoredPodcasts += 1
        }
        // Répare aussi une tentative interrompue après le déplacement du MP4
        // mais avant l'enregistrement de son chemin dans SwiftData.
        for (podcastID, digest) in podcastDigests where stagedPodcasts[podcastID] == nil {
            guard let podcast = try context.fetch(FetchDescriptor<PodcastRecord>()).first(where: { $0.id == podcastID }),
                  (try? podcastFileStore.fileURL(for: podcast.relativeFilePath)) == nil,
                  (try? podcastFileStore.finalFile(podcastID: podcastID, expectedSHA256: digest)) != nil else { continue }
            podcast.relativeFilePath = "Podcasts/\(podcastID.uuidString)/episode.mp4"
            podcast.importState = .ready
            try context.save()
            report.restoredPodcasts += 1
        }

        for (bookID, staged) in stagedEPUBs {
            guard let book = try fetchBook(id: bookID), (try? fileStore.fileURL(for: book.relativeFilePath)) == nil else {
                fileStore.discard(staged)
                continue
            }
            do {
                book.relativeFilePath = try fileStore.promote(staged, to: bookID)
                book.importState = .ready
                try context.save()
                report.restoredEPUBs += 1
            } catch {
                context.rollback()
                throw error
            }
        }
        // Répare le chemin d'un EPUB déjà promu lors d'une tentative précédente.
        for (bookID, digest) in epubDigests where stagedEPUBs[bookID] == nil {
            guard let book = try fetchBook(id: bookID),
                  (try? fileStore.fileURL(for: book.relativeFilePath)) == nil,
                  (try? fileStore.finalFile(bookID: bookID, expectedSHA256: digest)) != nil else { continue }
            book.relativeFilePath = fileStore.relativePath(forBookID: bookID)
            book.importState = .ready
            try context.save()
            report.restoredEPUBs += 1
        }
        return report
    }

    private func validate(payload: LoreBackupPayload, packageURL: URL, manifest: LoreBackupManifest) throws {
        try validatePayload(payload)
        let ids = Set(payload.books.map(\.id))
        let podcastIDs = Set(payload.podcasts.map(\.id))
        for id in manifest.epubSHA256ByBookID.keys where !ids.contains(id) { throw LoreBackupError.orphanEPUBDigest(id) }
        for id in manifest.missingEPUBBookIDs where !ids.contains(id) { throw LoreBackupError.orphanEPUBDigest(id) }
        for id in manifest.podcastSHA256ByPodcastID.keys where !podcastIDs.contains(id) { throw LoreBackupError.orphanEPUBDigest(id) }
        for id in manifest.missingPodcastIDs where !podcastIDs.contains(id) { throw LoreBackupError.orphanEPUBDigest(id) }
        try validateUnique(manifest.missingEPUBBookIDs, type: "EPUB manquants")
        let classifiedEPUBBookIDs = Set(manifest.epubSHA256ByBookID.keys).union(manifest.missingEPUBBookIDs)
        guard classifiedEPUBBookIDs == ids else { throw LoreBackupError.invalidPayloadDigest }
        guard Set(manifest.podcastSHA256ByPodcastID.keys).union(manifest.missingPodcastIDs) == podcastIDs else { throw LoreBackupError.invalidPayloadDigest }
        guard manifest.recordCounts["books"] == payload.books.count,
              manifest.recordCounts["sessions"] == payload.sessions.count,
              manifest.recordCounts["highlights"] == payload.highlights.count,
              manifest.recordCounts["vocabulary"] == payload.vocabulary.count,
              manifest.recordCounts["podcasts"] == payload.podcasts.count,
              manifest.recordCounts["collections"] == payload.collections.count,
              manifest.recordCounts["collectionMemberships"] == payload.collectionMemberships.count else { throw LoreBackupError.invalidPayloadDigest }
        for (id, digest) in manifest.epubSHA256ByBookID {
            guard payload.books.first(where: { $0.id == id })?.contentSHA256 == digest,
                  !manifest.missingEPUBBookIDs.contains(id) else { throw LoreBackupError.invalidEPUBDigest(id) }
            let url = packageURL.appendingPathComponent(Self.epubDirectoryName).appendingPathComponent("\(id.uuidString).epub")
            guard fileManager.fileExists(atPath: url.path), try fileStore.sha256(of: url) == digest else { throw LoreBackupError.invalidEPUBDigest(id) }
        }
        for (id, digest) in manifest.podcastSHA256ByPodcastID {
            guard payload.podcasts.first(where: { $0.id == id })?.contentSHA256 == digest,
                  !manifest.missingPodcastIDs.contains(id) else { throw LoreBackupError.invalidEPUBDigest(id) }
            let url = packageURL.appendingPathComponent(Self.podcastDirectoryName).appendingPathComponent("\(id.uuidString).mp4")
            guard fileManager.fileExists(atPath: url.path), try podcastFileStore.contentSHA256(of: url) == digest else { throw LoreBackupError.invalidEPUBDigest(id) }
        }
    }

    private func validatePayload(_ payload: LoreBackupPayload) throws {
        guard payload.formatVersion == LoreBackupPayload.currentVersion else { throw LoreBackupError.unsupportedVersion(payload.formatVersion) }
        let ids = Set(payload.books.map(\.id))
        try validateUnique(payload.books.map(\.id), type: "livres")
        try validateUnique(payload.sessions.map(\.id), type: "sessions")
        try validateUnique(payload.highlights.map(\.id), type: "surlignages")
        try validateUnique(payload.vocabulary.map(\.id), type: "mots")
        try validateUnique(payload.podcasts.map(\.id), type: "podcasts")
        try validateUnique(payload.collections.map(\.id), type: "collections")
        try validateUnique(payload.collectionMemberships.map(\.id), type: "appartenances")
        var digests = Set<String>()
        for book in payload.books {
            if book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                book.mediaType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw LoreBackupError.invalidRequiredFields(book.id)
            }
            if let digest = book.contentSHA256,
               digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) == nil {
                throw LoreBackupError.invalidContentDigest(book.id)
            }
            if let digest = book.contentSHA256, !digests.insert(digest).inserted { throw LoreBackupError.duplicateContentDigest(digest) }
            if let rating = book.rating, !(0...10).contains(rating) { throw LoreBackupError.invalidRating(book.id) }
            if let year = book.readingYear, !(1...9_999).contains(year) { throw LoreBackupError.invalidReadingYear(book.id) }
            if let locator = book.lastLocatorJSON {
                guard (try? LocatorPersistenceCodec.decode(.init(data: locator, schemaVersion: book.locatorSchemaVersion))) != nil else {
                    throw LoreBackupError.invalidLocator(book.id)
                }
            }
        }
        for book in payload.books where book.lastProgression.map({ !(0...1).contains($0) }) ?? false { throw LoreBackupError.invalidProgression(book.id) }
        for id in payload.sessions.map(\.bookID) + payload.highlights.map(\.bookID) + payload.vocabulary.map(\.bookID) where !ids.contains(id) { throw LoreBackupError.invalidReference(id) }
        for item in payload.highlights where (try? HighlightLocatorCodec.decode(.init(data: item.locatorJSON, schemaVersion: item.locatorSchemaVersion))) == nil { throw LoreBackupError.invalidLocator(item.id) }
        for item in payload.highlights where HighlightColor(rawValue: item.colorRawValue) == nil { throw LoreBackupError.invalidColor(item.id) }
        for item in payload.vocabulary where (try? HighlightLocatorCodec.decode(.init(data: item.locatorJSON, schemaVersion: item.locatorSchemaVersion))) == nil { throw LoreBackupError.invalidLocator(item.id) }
        var podcastDigests = Set<String>()
        for podcast in payload.podcasts {
            guard !podcast.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !podcast.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  podcast.lastPositionSeconds >= 0,
                  podcast.durationSeconds.map({ $0 > 0 }) ?? true else { throw LoreBackupError.invalidRequiredFields(podcast.id) }
            if let digest = podcast.contentSHA256 {
                guard digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw LoreBackupError.invalidContentDigest(podcast.id) }
                guard podcastDigests.insert(digest).inserted else { throw LoreBackupError.duplicateContentDigest(digest) }
            }
        }
        let collectionIDs = Set(payload.collections.map(\.id))
        guard Set(payload.collections.map(\.normalizedName)).count == payload.collections.count else { throw LoreBackupError.duplicateContentDigest("collection") }
        for collection in payload.collections where collection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || collection.normalizedName.isEmpty { throw LoreBackupError.invalidRequiredFields(collection.id) }
        for membership in payload.collectionMemberships where !ids.contains(membership.bookID) || !collectionIDs.contains(membership.collectionID) { throw LoreBackupError.invalidReference(membership.id) }
        let membershipKeys = payload.collectionMemberships.map { "\($0.collectionID.uuidString.lowercased())|\($0.bookID.uuidString.lowercased())" }
        guard Set(membershipKeys).count == membershipKeys.count else { throw LoreBackupError.duplicateContentDigest("appartenance") }
    }

    private func validateUnique(_ values: [UUID], type: String) throws {
        var seen = Set<UUID>()
        for value in values where !seen.insert(value).inserted { throw LoreBackupError.duplicateIdentifier(type, value) }
    }

    private func validateExistingChildren(_ payload: LoreBackupPayload) throws {
        let sessions = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ReadingSessionRecord>()).map { ($0.id, $0) })
        for value in payload.sessions {
            if let local = sessions[value.id],
               local.bookID != value.bookID || local.startedAt != value.startedAt ||
               local.lastActivityAt != value.lastActivityAt || local.endedAt != value.endedAt {
                throw LoreBackupError.conflictingRecord("session", value.id)
            }
        }
        let highlights = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<HighlightRecord>()).map { ($0.id, $0) })
        for value in payload.highlights {
            if let local = highlights[value.id],
               local.bookID != value.bookID || local.locatorJSON != value.locatorJSON ||
               local.locatorSchemaVersion != value.locatorSchemaVersion || local.text != value.text ||
               local.createdAt != value.createdAt || local.colorRawValue != value.colorRawValue {
                throw LoreBackupError.conflictingRecord("surlignage", value.id)
            }
        }
        let words = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<VocabularyRecord>()).map { ($0.id, $0) })
        for value in payload.vocabulary {
            if let local = words[value.id],
               local.bookID != value.bookID || local.locatorJSON != value.locatorJSON ||
               local.locatorSchemaVersion != value.locatorSchemaVersion || local.text != value.text ||
               local.createdAt != value.createdAt {
                throw LoreBackupError.conflictingRecord("mot", value.id)
            }
        }
        let podcasts = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<PodcastRecord>()).map { ($0.id, $0) })
        for value in payload.podcasts where podcasts[value.id].map({ Self.backupPodcast($0) != value }) == true {
            throw LoreBackupError.conflictingRecord("podcast", value.id)
        }
        let collections = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ManualCollectionRecord>()).map { ($0.id, $0) })
        for value in payload.collections {
            if let local = collections[value.id], local.name != value.name || local.normalizedName != value.normalizedName || local.createdAt != value.createdAt {
                throw LoreBackupError.conflictingRecord("collection", value.id)
            }
        }
        let memberships = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CollectionMembershipRecord>()).map { ($0.id, $0) })
        for value in payload.collectionMemberships {
            if let local = memberships[value.id], local.collectionID != value.collectionID || local.bookID != value.bookID || local.addedAt != value.addedAt {
                throw LoreBackupError.conflictingRecord("appartenance", value.id)
            }
        }
    }

    private func fetchBook(id: UUID) throws -> BookRecord? {
        var descriptor = FetchDescriptor<BookRecord>(predicate: #Predicate { $0.id == id }); descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func insertMissing<T>(_ values: [T], existing: Set<UUID>, id: KeyPath<T, UUID>, insert: (T) -> Void) throws {
        for value in values where !existing.contains(value[keyPath: id]) { insert(value) }
    }

    private static func backupBook(_ book: BookRecord) -> LoreBackupPayload.Book {
        .init(id: book.id, contentSHA256: book.contentSHA256, title: book.title, author: book.author, coverData: book.coverData, mediaType: book.mediaType, importedAt: book.importedAt, lastLocatorJSON: book.lastLocatorJSON, lastProgression: book.lastProgression, progressUpdatedAt: book.progressUpdatedAt, locatorSchemaVersion: book.locatorSchemaVersion, finishedAt: book.finishedAt, rating: book.rating, readingYear: book.readingYear, isHiddenFromResume: book.isHiddenFromResume)
    }

    private static func backupPodcast(_ podcast: PodcastRecord) -> LoreBackupPayload.Podcast {
        .init(id: podcast.id, contentSHA256: podcast.contentSHA256, title: podcast.title, originalFilename: podcast.originalFilename, importedAt: podcast.importedAt, durationSeconds: podcast.durationSeconds, lastPositionSeconds: podcast.lastPositionSeconds, progressUpdatedAt: podcast.progressUpdatedAt)
    }

    private static func record(from book: LoreBackupPayload.Book, relativeFilePath: String) -> BookRecord {
        BookRecord(id: book.id, contentSHA256: book.contentSHA256, title: book.title, author: book.author, coverData: book.coverData, relativeFilePath: relativeFilePath, mediaType: book.mediaType, importedAt: book.importedAt, lastLocatorJSON: book.lastLocatorJSON, lastProgression: book.lastProgression, progressUpdatedAt: book.progressUpdatedAt, locatorSchemaVersion: book.locatorSchemaVersion, finishedAt: book.finishedAt, rating: book.rating, readingYear: book.readingYear, isHiddenFromResume: book.isHiddenFromResume, importState: relativeFilePath.isEmpty ? .recoveryRequired : .ready)
    }

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
