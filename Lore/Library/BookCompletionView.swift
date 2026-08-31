import SwiftUI

struct BookCompletionView: View {
    let book: BookRecord
    let onSave: (Int?, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int?
    @State private var readingYear: Int

    private let currentYear = Calendar.autoupdatingCurrent.component(.year, from: .now)

    init(book: BookRecord, onSave: @escaping (Int?, Int) -> Void) {
        self.book = book
        self.onSave = onSave
        _rating = State(initialValue: book.rating)
        _readingYear = State(initialValue: book.readingYear ?? Calendar.autoupdatingCurrent.component(.year, from: .now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        BookCoverView(book: book)
                            .frame(width: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Livre terminé")
                                .font(.title3.weight(.semibold))
                            Text(book.title)
                                .font(.headline)
                                .lineLimit(2)
                            if let author = book.author {
                                Text(author)
                                    .font(.subheadline)
                                    .foregroundStyle(LoreTheme.secondaryInk)
                                    .lineLimit(1)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Votre note")
                            .font(.headline)
                        GeometryReader { geometry in
                            HStack(spacing: 2) {
                                ForEach(1...10, id: \.self) { star in
                                    Image(systemName: (rating ?? 0) >= star ? "star.fill" : "star")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle((rating ?? 0) >= star ? Color.orange : LoreTheme.secondaryInk)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { value in
                                let unit = max(1, geometry.size.width / 10)
                                rating = min(10, max(1, Int(value.location.x / unit) + 1))
                            })
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Note sur 10")
                            .accessibilityValue(rating.map { "\($0) sur 10" } ?? "Aucune note")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAdjustableAction { direction in
                                switch direction {
                                case .increment: rating = min(10, (rating ?? 0) + 1)
                                case .decrement: rating = max(0, (rating ?? 0) - 1)
                                @unknown default: break
                                }
                            }
                        }
                        .frame(height: 44)
                        Text(rating.map { "\($0)/10" } ?? "Aucune note")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(LoreTheme.secondaryInk)
                        Button("Noter 0/10") { rating = 0 }
                            .font(.caption.weight(.medium))
                        if rating != nil {
                            Button("Retirer la note") { rating = nil }
                                .font(.caption.weight(.medium))
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Année de lecture")
                            .font(.headline)
                        Stepper(value: $readingYear, in: 1...max(currentYear + 1, 2)) {
                            Text("\(readingYear)")
                                .font(.body.monospacedDigit())
                                .frame(minWidth: 52, alignment: .leading)
                        }
                        .accessibilityLabel("Année de lecture \(readingYear)")
                    }
                }
                .padding(.horizontal, LoreTheme.pageMargin)
                .padding(.vertical, 20)
            }
            .navigationTitle("Évaluer la lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(rating, readingYear)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .loreCanvas()
    }
}
