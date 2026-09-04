import SwiftUI

struct BookDetailView: View {
    let book: BookRecord
    let loadDetail: () throws -> LibraryViewModel.BookDetailData
    let onOpenBook: () -> Void
    let onOpenHighlights: () -> Void
    let onOpenDiscussion: () -> Void
    let collections: [ManualCollectionRecord]
    let isMember: (ManualCollectionRecord) -> Bool
    let onToggleCollection: (ManualCollectionRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var loadState: LoadState = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    ProgressView("Chargement des informations…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Chargement des informations du livre")
                case .missing:
                    ContentUnavailableView(
                        "Livre introuvable",
                        systemImage: "book.closed",
                        description: Text("Ce livre n’est plus présent dans la bibliothèque.")
                    )
                case let .failed(message):
                    ContentUnavailableView(
                        "Informations indisponibles",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                case let .loaded(detail):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            identity
                            progress
                            facts(detail)
                            collectionsSection
                            actions
                        }
                        .padding(.horizontal, LoreTheme.pageMargin)
                        .padding(.top, 10)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(LoreTheme.canvas)
            .navigationTitle("Détails du livre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .loreCanvas()
        .task(id: book.id) { loadSnapshot() }
    }

    private var identity: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    cover
                    identityText
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    cover
                    identityText
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var cover: some View {
        BookCoverView(book: book)
            .frame(width: 112)
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(book.readingStatus.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoreTheme.secondaryInk)
            Text(book.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let author = book.author?.nilIfBlank {
                Text(author)
                    .font(.body)
                    .foregroundStyle(LoreTheme.secondaryInk)
            } else {
                Text("Auteur non renseigné")
                    .font(.subheadline)
                    .foregroundStyle(LoreTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Progression")
                    .font(.headline)
                Spacer()
                Text(progressLabel)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            if let persistedProgress {
                LoreProgressBar(value: persistedProgress)
                    .accessibilityLabel("Progression")
                    .accessibilityValue(progressLabel)
            }
        }
    }

    private func facts(_ detail: LibraryViewModel.BookDetailData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Informations")
                .font(.headline)
                .padding(.bottom, 6)

            fact("Statut", book.readingStatus.title)
            fact("Note", book.rating.map { "\($0)/10" } ?? "Non renseignée")
            fact("Année de lecture", book.readingYear.map(String.init) ?? "Non renseignée")
            fact("Temps lu", Self.durationText(detail.totalReadingTime))
            if let firstReadAt = detail.firstReadAt {
                fact("Première lecture", Self.dateText(firstReadAt))
            }
            if let lastReadAt = detail.lastReadAt {
                fact("Dernière lecture", Self.dateText(lastReadAt))
            }
            fact("Terminé le", Self.dateText(book.finishedAt))
            fact("Ajouté le", Self.dateText(book.importedAt))
            fact("Surlignages", String(detail.highlightCount))
            fact("Notes personnelles", String(detail.noteCount), drawsDivider: false)
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collections")
                .font(.headline)

            if collections.isEmpty {
                Text("Aucune collection créée")
                    .font(.subheadline)
                    .foregroundStyle(LoreTheme.secondaryInk)
            } else {
                ForEach(collections) { collection in
                    Button {
                        onToggleCollection(collection)
                    } label: {
                        HStack {
                            Text(collection.name)
                                .foregroundStyle(LoreTheme.ink)
                            Spacer()
                            Image(systemName: isMember(collection) ? "checkmark.circle.fill" : "circle")
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isMember(collection) ? "Ajouté" : "Non ajouté")
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onOpenBook) {
                Label(book.readingStatus == .toRead ? "Commencer la lecture" : "Ouvrir le livre", systemImage: "book.pages")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(LoreTheme.ink)
            .foregroundStyle(LoreTheme.canvas)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        highlightsButton
                        discussionButton
                    }
                } else {
                    HStack(spacing: 10) {
                        highlightsButton
                        discussionButton
                    }
                }
            }
        }
    }

    private var highlightsButton: some View {
        Button(action: onOpenHighlights) {
            Label("Surlignages", systemImage: "highlighter")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var discussionButton: some View {
        Button(action: onOpenDiscussion) {
            Label("Discussion IA", systemImage: "sparkles")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private func fact(_ label: String, _ value: String, drawsDivider: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(LoreTheme.secondaryInk)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if drawsDivider { Divider() }
        }
        .accessibilityElement(children: .combine)
    }

    private var persistedProgress: Double? {
        book.lastProgression.map { min(max($0, 0), 1) }
    }

    private var progressLabel: String {
        persistedProgress?.formatted(.percent.precision(.fractionLength(0))) ?? "Non renseignée"
    }

    static func durationText(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return "Aucun temps enregistré" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3_600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: duration) ?? "Aucun temps enregistré"
    }

    static func dateText(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .omitted) ?? "Non renseignée"
    }

    private func loadSnapshot() {
        loadState = .loading
        do {
            loadState = .loaded(try loadDetail())
        } catch BookRepositoryError.bookNotFound {
            loadState = .missing
        } catch {
            loadState = .failed(
                (error as? LocalizedError)?.errorDescription
                    ?? "Les données locales n’ont pas pu être chargées."
            )
        }
    }

    private enum LoadState {
        case loading
        case loaded(LibraryViewModel.BookDetailData)
        case missing
        case failed(String)
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
