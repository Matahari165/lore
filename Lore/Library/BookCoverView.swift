import SwiftUI
import UIKit

struct BookCoverView: View {
    private let coverData: Data?
    private let title: String
    private let cornerRadius: CGFloat?

    init(book: BookRecord, cornerRadius: CGFloat? = nil) {
        self.init(coverData: book.coverData, title: book.title, cornerRadius: cornerRadius)
    }

    init(coverData: Data?, title: String, cornerRadius: CGFloat? = nil) {
        self.coverData = coverData
        self.title = title
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        let radius = cornerRadius ?? LoreTheme.coverRadius
        ZStack {
            // The cover slot stays portrait even when an EPUB provides a wide,
            // square, or otherwise unusual image. The neutral surface becomes
            // the letterbox instead of allowing the image to crop or stretch.
            LoreTheme.canvas

            if let coverData, let image = UIImage(data: coverData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed.fill")
                        .font(.title2)
                    Text(title)
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }
                .foregroundStyle(LoreTheme.ink)
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(LoreTheme.coverAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(LoreTheme.hairline, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
