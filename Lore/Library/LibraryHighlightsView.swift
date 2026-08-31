import SwiftUI

struct LibraryHighlightsView: View {
    let book: BookRecord
    let highlights: [ReaderHighlight]
    let onOpenHighlight: ((ReaderHighlight) -> Void)?
    let onDiscussHighlight: ((ReaderHighlight) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    ContentUnavailableView(
                        "Aucun passage surligné",
                        systemImage: "highlighter",
                        description: Text("Les passages que vous surlignez dans le lecteur apparaîtront ici.")
                    )
                } else {
                    List(highlights) { highlight in
                        Group {
                            if let onOpenHighlight {
                                Button { onOpenHighlight(highlight) } label: {
                                    highlightLabel(highlight)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Ouvre ce passage dans le lecteur")
                            } else {
                                highlightLabel(highlight)
                            }
                        }
                        .contextMenu {
                            if let onDiscussHighlight {
                                Button("Discuter de ce passage", systemImage: "sparkles") {
                                    dismiss()
                                    onDiscussHighlight(highlight)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Passages surlignés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .loreCanvas()
    }

    private func highlightLabel(_ highlight: ReaderHighlight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(highlight.text)
                .foregroundStyle(LoreTheme.ink)
                .lineLimit(6)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Text(highlight.createdAt, format: .dateTime.day().month().year())
                .font(.caption)
                .foregroundStyle(LoreTheme.secondaryInk)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Passage de \(book.title) : \(highlight.text)")
    }
}
