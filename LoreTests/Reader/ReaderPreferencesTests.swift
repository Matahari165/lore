import Foundation
import ReadiumNavigator
import ReadiumShared
import Testing
@testable import Lore

@MainActor
struct ReaderPreferencesTests {
    @Test func defaultsAreSafeWhenStorageIsMissingOrCorrupt() {
        let fixture = DefaultsFixture()
        #expect(fixture.store.load() == .default)

        fixture.defaults.set(Data("invalid".utf8), forKey: fixture.key)
        #expect(fixture.store.load() == .default)
    }

    @Test func preferencesRoundTripAndNormalizeBounds() throws {
        let fixture = DefaultsFixture()
        try fixture.store.save(ReaderPreferences(
            fontSize: 9,
            typeface: .sansSerif,
            lineHeight: 0.2,
            appearance: .dark
        ))

        let restored = fixture.store.load()
        #expect(restored.fontSize == 2.0)
        #expect(restored.typeface == .sansSerif)
        #expect(restored.lineHeight == 1.0)
        #expect(restored.appearance == .dark)
    }

    @Test func readiumMappingDisablesPublisherStylesForEffectiveLineHeight() {
        let preferences = ReaderPreferences(
            fontSize: 1.3,
            typeface: .sansSerif,
            lineHeight: 1.7,
            appearance: .dark,
            horizontalMargins: 1.75,
            verticalMargins: 2
        ).readiumValue

        #expect(preferences.fontSize == 1.3)
        #expect(preferences.fontFamily == .sansSerif)
        #expect(preferences.lineHeight == 1.7)
        #expect(preferences.pageMargins == 1.75)
        #expect(preferences.publisherStyles == false)
        #expect(preferences.theme == .dark)
        #expect(preferences.imageFilter == .darken)
    }

    @Test func defaultsPreservePublisherTypographyAndLineHeight() {
        let preferences = ReaderPreferences.default.readiumValue
        #expect(preferences.fontFamily == nil)
        #expect(preferences.lineHeight == nil)
        #expect(preferences.pageMargins == 1)
        #expect(preferences.publisherStyles == false)
    }

    @Test func quickFontAdjustmentsUseStableStepsAndRespectBounds() {
        var preferences = ReaderPreferences.default

        preferences.adjustFontSize(by: 1)
        #expect(preferences.fontSize == 1.1)

        preferences.adjustFontSize(by: 100)
        #expect(preferences.fontSize == ReaderPreferences.fontSizeRange.upperBound)

        preferences.adjustFontSize(by: -100)
        #expect(preferences.fontSize == ReaderPreferences.fontSizeRange.lowerBound)
    }

    @Test func resetRestoresEveryReaderPreference() {
        var preferences = ReaderPreferences(
            fontSize: 1.7,
            typeface: .sansSerif,
            lineHeight: 1.8,
            appearance: .dark,
            horizontalMargins: 2,
            verticalMargins: 2.5
        )

        preferences.reset()

        #expect(preferences == .default)
    }

    @Test func olderStoredPreferencesReceiveSafeMarginDefaults() throws {
        let fixture = DefaultsFixture()
        fixture.defaults.set(Data(#"{"fontSize":1.4,"typeface":"serif","appearance":"dark"}"#.utf8), forKey: fixture.key)

        let restored = fixture.store.load()

        #expect(restored.fontSize == 1.4)
        #expect(restored.typeface == .serif)
        #expect(restored.appearance == .dark)
        #expect(restored.horizontalMargins == 1)
        #expect(restored.verticalMargins == 1)
    }

    @Test func marginValuesAreClamped() {
        let preferences = ReaderPreferences(horizontalMargins: 9, verticalMargins: -4)

        #expect(preferences.horizontalMargins == ReaderPreferences.horizontalMarginsRange.upperBound)
        #expect(preferences.verticalMargins == ReaderPreferences.verticalMarginsRange.lowerBound)
    }

    @Test func chapterTreeKeepsDepthFallbackTitlesAndUniqueStructuralIDs() {
        let repeatedHref = "chapter.xhtml"
        let chapters = ReaderChapter.flatten([
            Link(href: repeatedHref, title: "Partie", children: [
                Link(href: repeatedHref, title: nil),
            ]),
            Link(href: repeatedHref, title: "Suite"),
        ])

        #expect(chapters.map(\.depth) == [0, 1, 0])
        #expect(chapters.map(\.title) == ["Partie", "Chapitre sans titre", "Suite"])
        #expect(Set(chapters.map(\.id)).count == 3)
    }
}

@MainActor
private struct DefaultsFixture {
    let key = "reader-preferences-tests"
    let suite = "Lore.ReaderPreferencesTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let store: UserDefaultsReaderPreferencesStore

    init() {
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        store = UserDefaultsReaderPreferencesStore(defaults: defaults, key: key)
    }
}
