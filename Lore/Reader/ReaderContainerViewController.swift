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

        let navigator = session.contentViewController
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { @MainActor [weak self] in
            await self?.session.reinforceSelectionAppearance()
        }
    }

    @objc func highlightSelection(_ sender: Any?) {
        session.highlightCurrentSelection()
    }

    @objc func explainSelection(_ sender: Any?) {
        session.explainCurrentSelection()
    }

    @objc func addSelectionToVocabulary(_ sender: Any?) {
        session.addCurrentSelectionToVocabulary()
    }
}
