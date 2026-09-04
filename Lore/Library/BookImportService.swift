import Foundation

enum BookImportResult {
    case imported(BookRecord)
    case alreadyImported(BookRecord)

    var book: BookRecord {
        switch self {
        case let .imported(book), let .alreadyImported(book): book
        }
    }
}

@MainActor
private final class BookImportGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

struct ImportReconciliationReport {
    var recoveredBookIDs: [UUID] = []
    var recoveryRequiredBookIDs: [UUID] = []
    var files = BookFileReconciliationReport()
}

@MainActor
final class BookImportService {
    private let repository: BookRepository
    private let fileStore: BookFileStore
    private let validator: any EPUBImportValidating
    private let gate = BookImportGate()

    init(repository: BookRepository, fileStore: BookFileStore, publicationService: any EPUBImportValidating) {
        self.repository = repository
        self.fileStore = fileStore
        validator = publicationService
    }

    func importEPUB(from sourceURL: URL) async throws -> BookImportResult {
        await gate.acquire()
        defer { gate.release() }

        let fileStore = self.fileStore
        let staged = try await Task.detached {
            try fileStore.stageEPUB(from: sourceURL)
        }.value
        do {
            try Task.checkCancellation()
        } catch {
            fileStore.discard(staged)
            throw error
        }
        if let existing = try repository.book(contentSHA256: staged.contentSHA256) {
            if existing.importState == .ready,
               (try? fileStore.finalFile(bookID: existing.id, expectedSHA256: staged.contentSHA256)) != nil {
                fileStore.discard(staged)
                return .alreadyImported(existing)
            }
            if existing.importState != .ready, (try? recoverImport(existing)) != nil {
                fileStore.discard(staged)
                return .alreadyImported(existing)
            }
            return try await repair(existing, using: staged)
        }

        do {
            let metadata = try await validator.validateEPUBForImport(at: staged.fileURL)
            try Task.checkCancellation()
            let book = BookRecord(
                contentSHA256: staged.contentSHA256,
                title: metadata.title?.nonEmpty ?? sourceURL.deletingPathExtension().lastPathComponent,
                author: metadata.author?.nonEmpty,
                coverData: metadata.coverData,
                relativeFilePath: "",
                mediaType: metadata.mediaType,
                importState: .pending,
                stagingToken: staged.token
            )
            do {
                try repository.add(book)
            } catch {
                fileStore.discard(staged)
                if let duplicate = try? repository.book(contentSHA256: staged.contentSHA256) {
                    return .alreadyImported(duplicate)
                }
                throw error
            }

            let bookID = book.id
            let relativePath = try await Task.detached {
                try fileStore.promote(staged, to: bookID)
            }.value
            try repository.confirmImport(bookID: book.id, relativeFilePath: relativePath)
            return .imported(book)
        } catch {
            // A staging that is not referenced by a pending record is disposable.
            if let reserved = try? repository.book(contentSHA256: staged.contentSHA256) {
                do {
                    try recoverImport(reserved)
                } catch {
                    try? repository.markRecoveryRequired(bookID: reserved.id)
                }
            } else {
                fileStore.discard(staged)
            }
            throw error
        }
    }

    func reconcileImports(now: Date = .now) throws -> ImportReconciliationReport {
        var report = ImportReconciliationReport()
        for book in try repository.pendingImports() {
            do {
                try recoverImport(book)
                report.recoveredBookIDs.append(book.id)
            } catch {
                try repository.markRecoveryRequired(bookID: book.id)
                report.recoveryRequiredBookIDs.append(book.id)
            }
        }

        let books = try repository.books()
        report.files = try fileStore.reconcile(
            referencedBookIDs: Set(books.map(\.id)),
            referencedStagingTokens: Set(books.compactMap(\.stagingToken)),
            now: now
        )
        return report
    }

    private func recoverImport(_ book: BookRecord) throws {
        guard let digest = book.contentSHA256 else {
            try repository.markRecoveryRequired(bookID: book.id)
            throw BookFileStoreError.storedFileMissing
        }
        if (try? fileStore.finalFile(bookID: book.id, expectedSHA256: digest)) != nil {
            try repository.confirmImport(
                bookID: book.id,
                relativeFilePath: fileStore.relativePath(forBookID: book.id)
            )
        } else if let token = book.stagingToken {
            let staged = try fileStore.stagedFile(token: token, expectedSHA256: digest)
            _ = try fileStore.quarantineFinalDirectory(bookID: book.id)
            let path = try fileStore.promote(staged, to: book.id)
            try repository.confirmImport(bookID: book.id, relativeFilePath: path)
        } else {
            try repository.markRecoveryRequired(bookID: book.id)
            throw BookFileStoreError.storedFileMissing
        }
    }

    private func repair(_ book: BookRecord, using staged: StagedBookFile) async throws -> BookImportResult {
        do {
            let metadata = try await validator.validateEPUBForImport(at: staged.fileURL)
            try repository.prepareRepair(bookID: book.id, stagingToken: staged.token, metadata: metadata)
            _ = try fileStore.quarantineFinalDirectory(bookID: book.id)
            let path = try fileStore.promote(staged, to: book.id)
            try repository.confirmImport(bookID: book.id, relativeFilePath: path)
            return .alreadyImported(book)
        } catch {
            let referencesNewStaging = (try? repository.book(id: book.id)?.stagingToken) == staged.token
            if !referencesNewStaging { fileStore.discard(staged) }
            throw error
        }
    }
}

private extension String {
    var nonEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
