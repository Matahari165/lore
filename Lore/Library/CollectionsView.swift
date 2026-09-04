import SwiftUI

struct CollectionsView: View {
    let model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsNewCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Intelligentes") {
                    ForEach(model.smartCollections) { collection in
                        NavigationLink {
                            CollectionBooksView(title: collection.title, books: model.books(in: collection), model: model)
                        } label: {
                            collectionRow(collection.title, count: model.books(in: collection).count)
                        }
                    }
                }

                Section("Mes collections") {
                    if model.manualCollections.isEmpty {
                        ContentUnavailableView(
                            "Aucune collection",
                            systemImage: "books.vertical",
                            description: Text("Créez une collection, puis ajoutez-y des livres depuis leur appui long ou leur fiche.")
                        )
                    } else {
                        ForEach(model.manualCollections) { collection in
                            NavigationLink {
                                CollectionBooksView(title: collection.name, books: model.books(in: collection), model: model)
                            } label: {
                                collectionRow(collection.name, count: model.books(in: collection).count)
                            }
                            .swipeActions {
                                Button("Supprimer", role: .destructive) { model.deleteCollection(collection) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nouvelle collection", systemImage: "plus") { showsNewCollection = true }
                }
            }
            .alert("Nouvelle collection", isPresented: $showsNewCollection) {
                TextField("Nom", text: $newCollectionName)
                Button("Annuler", role: .cancel) { newCollectionName = "" }
                Button("Créer") {
                    model.createCollection(named: newCollectionName)
                    newCollectionName = ""
                }
            } message: {
                Text("Les livres ne sont pas copiés : la collection conserve seulement leur référence.")
            }
        }
    }

    private func collectionRow(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(count, format: .number)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(count) livre\(count > 1 ? "s" : "")")
        }
    }
}

struct BookDetailsView: View {
    let book: BookRecord
    let model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        BookCoverView(book: book).frame(width: 84)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(book.title).font(.headline)
                            if let author = book.author { Text(author).foregroundStyle(.secondary) }
                            Text(book.readingStatus.title).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Section("Collections") {
                    if model.manualCollections.isEmpty {
                        Text("Créez d’abord une collection depuis la Bibliothèque.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.manualCollections) { collection in
                            Button {
                                model.toggleMembership(of: book, in: collection)
                            } label: {
                                HStack {
                                    Text(collection.name).foregroundStyle(.primary)
                                    Spacer()
                                    if model.isMember(book, of: collection) {
                                        Image(systemName: "checkmark").accessibilityHidden(true)
                                    }
                                }
                            }
                            .accessibilityValue(model.isMember(book, of: collection) ? "Ajouté" : "Non ajouté")
                        }
                    }
                }
            }
            .navigationTitle("Fiche du livre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

private struct CollectionBooksView: View {
    let title: String
    let books: [BookRecord]
    let model: LibraryViewModel

    var body: some View {
        Group {
            if books.isEmpty {
                ContentUnavailableView("Aucun livre", systemImage: "books.vertical", description: Text("Cette collection est vide."))
            } else {
                List(books) { book in
                    Button { Task { await model.open(book) } } label: {
                        HStack(spacing: 12) {
                            BookCoverView(book: book).frame(width: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(book.title).font(.headline).foregroundStyle(.primary)
                                if let author = book.author { Text(author).font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .accessibilityLabel("Ouvrir \(book.title)")
                }
            }
        }
        .navigationTitle(title)
    }
}
