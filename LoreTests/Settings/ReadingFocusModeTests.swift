import Foundation
import Testing
import UserNotifications
@testable import Lore

@MainActor
struct ReadingFocusModeTests {
    @Test func modeIsOptionalAndPersistsTheChoice() throws {
        let suiteName = "ReadingFocusModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let mode = ReadingFocusMode(defaults: defaults)

        #expect(!mode.isEnabled)
        mode.setEnabled(true)
        #expect(mode.isEnabled)
        #expect(ReadingFocusMode(defaults: defaults).isEnabled)

        #expect(!mode.silencesLoreInterruptions)
        mode.setReaderActive(true)
        #expect(mode.silencesLoreInterruptions)
        mode.setReaderActive(false)
        #expect(!mode.silencesLoreInterruptions)
    }

    @Test func notificationPresentationIsSilentOnlyDuringInternalFocus() {
        let silent = DailyGoalForegroundDelegate.presentationOptions(
            silencesLoreInterruptions: true
        )
        #expect(silent == [.list])

        let standard = DailyGoalForegroundDelegate.presentationOptions(
            silencesLoreInterruptions: false
        )
        #expect(standard == [.banner, .list, .sound])
    }

    @Test func interruptionsAreSilencedOnlyWhileEnabledReaderIsActive() {
        #expect(!ReadingFocusMode.shouldSilenceLoreInterruptions(isEnabled: false, isReaderActive: false))
        #expect(!ReadingFocusMode.shouldSilenceLoreInterruptions(isEnabled: true, isReaderActive: false))
        #expect(!ReadingFocusMode.shouldSilenceLoreInterruptions(isEnabled: false, isReaderActive: true))
        #expect(ReadingFocusMode.shouldSilenceLoreInterruptions(isEnabled: true, isReaderActive: true))
    }

    @Test func systemGuideDoesNotClaimDirectFocusControl() {
        #expect(ReadingFocusGuide.steps.count == 3)
        #expect(ReadingFocusGuide.steps[1].detail.contains("Lore"))
        #expect(ReadingFocusGuide.limitation.contains("ne peut pas"))
        #expect(ReadingFocusGuide.limitation.contains("l’app entière"))
    }
}
