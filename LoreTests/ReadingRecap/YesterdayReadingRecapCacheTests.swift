import Foundation
import Testing
@testable import Lore

struct YesterdayReadingRecapCacheTests {
    @Test func savesAndReturnsOneRecapPerDay() throws {
        let defaults = try freshDefaults()
        let cache = YesterdayReadingRecapCache(defaults: defaults)
        let day1 = Date(timeIntervalSinceReferenceDate: 100_000)
        let day2 = Date(timeIntervalSinceReferenceDate: 200_000)

        try cache.save("# Hier 1", dayStart: day1, fingerprint: "fp1")
        try cache.save("# Hier 2", dayStart: day2, fingerprint: "fp2")

        #expect(cache.recap(dayStart: day1, fingerprint: "fp1") == "# Hier 1")
        #expect(cache.recap(dayStart: day2, fingerprint: "fp2") == "# Hier 2")
        #expect(cache.recap(dayStart: day1, fingerprint: "other") == nil)
    }

    @Test func neverCachesEmptyTextOrFailures() throws {
        let defaults = try freshDefaults()
        let cache = YesterdayReadingRecapCache(defaults: defaults)
        let day = Date(timeIntervalSinceReferenceDate: 100_000)

        // Un texte vide ou un message d'erreur ne doit jamais masquer une future
        // tentative réussie : la sauvegarde est un no-op et l'historique reste vide.
        try cache.save("   \n  ", dayStart: day, fingerprint: "fp")

        #expect(cache.recap(dayStart: day, fingerprint: "fp") == nil)
        #expect(cache.recapHistory().isEmpty)
    }

    @Test func historyListsDaysFromNewestToOldest() throws {
        let defaults = try freshDefaults()
        let cache = YesterdayReadingRecapCache(defaults: defaults)
        let day1 = Date(timeIntervalSinceReferenceDate: 100_000)
        let day2 = Date(timeIntervalSinceReferenceDate: 200_000)
        let day3 = Date(timeIntervalSinceReferenceDate: 300_000)

        try cache.save("un", dayStart: day1, fingerprint: "fp")
        try cache.save("trois", dayStart: day3, fingerprint: "fp")
        try cache.save("deux", dayStart: day2, fingerprint: "fp")

        let history = cache.recapHistory()
        #expect(history.map(\.markdown) == ["trois", "deux", "un"])
        #expect(history.map(\.dayStart) == [day3, day2, day1])
    }

    @Test func purgesEntriesOlderThan30Days() throws {
        let defaults = try freshDefaults()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let cache = YesterdayReadingRecapCache(defaults: defaults, calendar: calendar)
        let recent = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31)))
        let old = try #require(calendar.date(byAdding: .day, value: -40, to: recent))

        try cache.save("ancien", dayStart: old, fingerprint: "fp")
        #expect(cache.recap(dayStart: old, fingerprint: "fp") == "ancien")

        try cache.save("récent", dayStart: recent, fingerprint: "fp")

        #expect(cache.recap(dayStart: old, fingerprint: "fp") == nil)
        #expect(cache.recap(dayStart: recent, fingerprint: "fp") == "récent")
        #expect(cache.recapHistory().map(\.markdown) == ["récent"])
    }

    private func freshDefaults() throws -> UserDefaults {
        let suiteName = "YesterdayRecapCache-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
