import SwiftUI

struct LoreProgressBar: View {
    let value: Double
    var fill: Color = LoreTheme.ink
    var track: Color = LoreTheme.secondaryInk.opacity(0.22)
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
