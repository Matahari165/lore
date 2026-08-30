import SwiftUI
import UIKit

enum LoreTheme {
    static let canvas = adaptiveColor(
        light: UIColor(red: 244 / 255, green: 245 / 255, blue: 242 / 255, alpha: 1),
        dark: UIColor(red: 16 / 255, green: 20 / 255, blue: 27 / 255, alpha: 1)
    )
    static let ink = adaptiveColor(
        light: UIColor(red: 20 / 255, green: 35 / 255, blue: 59 / 255, alpha: 1),
        dark: UIColor(red: 231 / 255, green: 236 / 255, blue: 244 / 255, alpha: 1)
    )
    static let secondaryInk = adaptiveColor(
        light: UIColor(red: 91 / 255, green: 101 / 255, blue: 116 / 255, alpha: 1),
        dark: UIColor(red: 170 / 255, green: 179 / 255, blue: 192 / 255, alpha: 1)
    )
    static let hairline = adaptiveColor(
        light: UIColor(red: 215 / 255, green: 218 / 255, blue: 219 / 255, alpha: 1),
        dark: UIColor(red: 54 / 255, green: 61 / 255, blue: 72 / 255, alpha: 1)
    )

    static let pageMargin: CGFloat = 20
    static let coverRadius: CGFloat = 6

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension View {
    func loreCanvas() -> some View {
        background(LoreTheme.canvas.ignoresSafeArea())
            .tint(LoreTheme.ink)
            .foregroundStyle(LoreTheme.ink)
    }
}
