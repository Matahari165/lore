import SwiftUI

struct ReaderScreen: View {
    let presentation: LibraryViewModel.ReaderPresentation
    let onClose: () -> Void

    @State private var showsControls = true

    var body: some View {
        ZStack(alignment: .top) {
            ReaderView(session: presentation.session)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { showsControls.toggle() } }

            if showsControls {
                HStack(spacing: 12) {
                    Button("Fermer", systemImage: "chevron.down") {
                        closeReader()
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Fermer le lecteur")

                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer()
                }
                .foregroundStyle(LoreTheme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .statusBarHidden(!showsControls)
        .persistentSystemOverlays(showsControls ? .automatic : .hidden)
        .accessibilityAction(.escape) {
            closeReader()
        }
    }

    private func closeReader() {
        Task {
            await presentation.session.close()
            onClose()
        }
    }
}
