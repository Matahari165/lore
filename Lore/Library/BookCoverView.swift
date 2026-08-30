import SwiftUI
import UIKit

struct BookCoverView: View {
    let book: BookRecord

    var body: some View {
        Group {
            if let data = book.coverData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LoreTheme.ink
                    VStack(spacing: 10) {
                        Image(systemName: "book.closed.fill")
                            .font(.title2)
                        Text(book.title)
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                    }
                    .foregroundStyle(LoreTheme.canvas)
                    .padding(14)
                }
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: LoreTheme.coverRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LoreTheme.coverRadius, style: .continuous)
                .stroke(LoreTheme.hairline, lineWidth: 0.5)
        }
        .shadow(color: LoreTheme.ink.opacity(0.13), radius: 7, y: 4)
        .accessibilityHidden(true)
    }
}
