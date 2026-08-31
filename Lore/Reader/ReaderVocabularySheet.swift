import SwiftUI
import UIKit

struct ReaderVocabularySheet: View {
    let items: [VocabularyItem]
    let onSelect: (VocabularyItem) -> Void
    let onDelete: (VocabularyItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: VocabularyItem?
    @State private var showsCopyConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Aucun vocabulaire",
                        systemImage: "character.book.closed",
                        description: Text("Sélectionnez un mot ou une phrase, puis touchez Vocabulaire.")
                    )
                } else {
                    List(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.text)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Text(item.createdAt, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Revient au passage d’origine")
                        .swipeActions {
                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                pendingDeletion = item
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vocabulaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !items.isEmpty {
                        ShareLink(item: exportText) {
                            Label("Partager tout", systemImage: "square.and.arrow.up")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Partager tout le vocabulaire")

                        Button("Copier tout", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = exportText
                            showsCopyConfirmation = true
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
            .alert("Vocabulaire copié", isPresented: $showsCopyConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Les \(items.count) passages ont été copiés, séparés par une ligne vide.")
            }
            .confirmationDialog(
                "Supprimer ce passage du vocabulaire ?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    guard let pendingDeletion else { return }
                    onDelete(pendingDeletion)
                    self.pendingDeletion = nil
                }
                Button("Annuler", role: .cancel) { pendingDeletion = nil }
            }
        }
    }

    private var exportText: String {
        items
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.text)
            .joined(separator: "\n\n")
    }
}
