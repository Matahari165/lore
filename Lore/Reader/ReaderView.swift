import SwiftUI

struct ReaderView: View {
    @Environment(\.scenePhase) private var scenePhase

    let session: ReaderSessionController

    var body: some View {
        ReaderViewControllerBridge(session: session)
            .ignoresSafeArea()
            .task(id: scenePhase) {
                await session.handleLifecycle(scenePhase.readerLifecycleState)
            }
            .onDisappear {
                Task { await session.close() }
            }
    }
}

private struct ReaderViewControllerBridge: UIViewControllerRepresentable {
    let session: ReaderSessionController

    func makeUIViewController(context: Context) -> ReaderContainerViewController {
        ReaderContainerViewController(session: session)
    }

    func updateUIViewController(_ uiViewController: ReaderContainerViewController, context: Context) {}
}

private extension ScenePhase {
    var readerLifecycleState: ReaderLifecycleState {
        switch self {
        case .active: .active
        case .inactive: .inactive
        case .background: .background
        @unknown default: .inactive
        }
    }
}
