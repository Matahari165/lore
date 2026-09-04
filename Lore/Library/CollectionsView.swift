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
