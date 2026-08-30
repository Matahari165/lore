import ReadiumNavigator
import UIKit

/// UIKit host using child-controller containment. The Readium controller is
/// composed into Lore and is never subclassed.
@MainActor
final class ReaderContainerViewController: UIViewController {
    let session: ReaderSessionController

    init(session: ReaderSessionController) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let navigator = session.navigator
        addChild(navigator)
        navigator.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigator.view)
        NSLayoutConstraint.activate([
            navigator.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigator.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigator.view.topAnchor.constraint(equalTo: view.topAnchor),
            navigator.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        navigator.didMove(toParent: self)
    }
}
