import SwiftUI

enum LoreTheme {
    static let canvas = Color(red: 244 / 255, green: 245 / 255, blue: 242 / 255)
    static let ink = Color(red: 20 / 255, green: 35 / 255, blue: 59 / 255)
    static let secondaryInk = ink.opacity(0.64)
    static let hairline = ink.opacity(0.12)

    static let pageMargin: CGFloat = 20
    static let coverRadius: CGFloat = 6
}

extension View {
    func loreCanvas() -> some View {
        background(LoreTheme.canvas.ignoresSafeArea())
            .tint(LoreTheme.ink)
            .foregroundStyle(LoreTheme.ink)
    }
}
