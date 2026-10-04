import AVFoundation
import Foundation
import ReadiumShared

/// Coordinateur audio dédié à la synthèse vocale locale dans Lore.
///
/// Implémente `AudioSessionManaging` pour s'interfacer avec le lecteur
/// tout en garantissant :
/// 1. La poursuite de l'audio écran verrouillé et en arrière-plan (catégorie `.playback`, mode `.spokenAudio`).
/// 2. La préservation de la session active en pause pour maintenir la réactivité de `MPRemoteCommandCenter`.
/// 3. La mise en pause synchrone et sans fuite au retrait des écouteurs/AirPods (`.oldDeviceUnavailable`).
/// 4. La gestion robuste et typée des interruptions système (appels, alarmes).
@MainActor
final class LoreTTSAudioSessionCoordinator: AudioSessionManaging {
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

    // MARK: - AudioSessionManaging

    nonisolated func start(with user: AudioSessionUser, isPlaying: Bool) {
        Task { @MainActor in
            self.activateSession()
        }
    }

    nonisolated func end(for user: AudioSessionUser) {
        Task { @MainActor in
            self.deactivateSession()
        }
    }

    nonisolated func user(_ user: AudioSessionUser, didChangePlaying isPlaying: Bool) {
        Task { @MainActor in
            if isPlaying {
                self.activateSession()
            }
        }
    }

    // MARK: - Gestion de session

    func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
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

            MainActor.assumeIsolated {
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

            MainActor.assumeIsolated {
                guard let self, let reasonRaw, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
                if reason == .oldDeviceUnavailable {
                    self.onRouteChangeOldDeviceUnavailable?()
                }
            }
        }
    }
}
