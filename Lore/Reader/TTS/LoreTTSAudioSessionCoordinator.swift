import AVFoundation
import Foundation
/// Coordinateur audio dédié à la synthèse vocale locale dans Lore.
///
/// Garantit :
/// 1. La poursuite de l'audio écran verrouillé et en arrière-plan (catégorie `.playback`, mode `.default`).
/// 2. La préservation de la session active en pause pour maintenir la réactivité de `MPRemoteCommandCenter`.
/// 3. La mise en pause synchrone et sans fuite au retrait des écouteurs/AirPods (`.oldDeviceUnavailable`).
/// 4. La gestion robuste et typée des interruptions système (appels, alarmes).
@MainActor
final class LoreTTSAudioSessionCoordinator {
    private var isSessionActive = false
    private nonisolated(unsafe) var interruptionObserver: NSObjectProtocol?
    private nonisolated(unsafe) var routeChangeObserver: NSObjectProtocol?

    var onInterruptionBegan: (@MainActor () -> Void)?
    var onInterruptionEnded: (@MainActor (_ shouldResume: Bool) -> Void)?
    var onRouteChangeOldDeviceUnavailable: (@MainActor () -> Void)?

    init() {
        observeAudioSessionNotifications()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

    // MARK: - Gestion de session

    func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            isSessionActive = true
        } catch {
            // Non bloquant : tentative poursuivie
        }
    }

    func deactivateSession() {
        guard isSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isSessionActive = false
        } catch {
            // Ignoré lors de la fermeture
        }
    }

    // MARK: - Notifications système

    private func observeAudioSessionNotifications() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo
            let rawType = (info?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
                ?? (info?[AVAudioSessionInterruptionTypeKey] as? UInt)
            let optionsRaw = (info?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue
                ?? (info?[AVAudioSessionInterruptionOptionKey] as? UInt)
                ?? 0

            // `Task` plutôt que `MainActor.assumeIsolated` : ce bloc s'exécute
            // sur le main thread mais hors contexte MainActor, où
            // `assumeIsolated` piège et tue l'app (appel entrant, Siri…).
            Task { @MainActor [weak self] in
                guard let self, let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                switch type {
                case .began:
                    self.onInterruptionBegan?()
                case .ended:
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                    let shouldResume = options.contains(.shouldResume)
                    if shouldResume {
                        self.activateSession()
                    }
                    self.onInterruptionEnded?(shouldResume)
                @unknown default:
                    self.onInterruptionBegan?()
                }
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo
            let reasonRaw = (info?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
                ?? (info?[AVAudioSessionRouteChangeReasonKey] as? UInt)

            // Même raison que ci-dessus : `Task` au lieu d'`assumeIsolated`.
            Task { @MainActor [weak self] in
                guard let self, let reasonRaw, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
                if reason == .oldDeviceUnavailable {
                    self.onRouteChangeOldDeviceUnavailable?()
                }
            }
        }
    }
}
