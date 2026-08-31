import Foundation
import ReadiumNavigator

struct ReaderPreferences: Codable, Equatable, Sendable {
    static let fontSizeRange = 0.8 ... 2.0
    static let fontSizeStep = 0.1
    static let lineHeightRange = 1.0 ... 2.0

    enum Typeface: String, Codable, CaseIterable, Sendable {
        case publisher
        case serif
        case sansSerif

        var label: String {
            switch self {
            case .publisher: "Livre"
            case .serif: "Sérif"
            case .sansSerif: "Sans sérif"
            }
        }

        var readiumValue: FontFamily? {
            switch self {
            case .publisher: nil
            case .serif: .serif
            case .sansSerif: .sansSerif
            }
        }
    }

    enum Appearance: String, Codable, CaseIterable, Sendable {
        case light
        case dark

        var label: String { self == .light ? "Clair" : "Sombre" }
        var readiumValue: Theme { self == .light ? .light : .dark }
    }

    static let `default` = ReaderPreferences()

    var fontSize: Double = 1.0
    var typeface: Typeface = .publisher
    var lineHeight: Double?
    var appearance: Appearance = .light

    mutating func normalize() {
        fontSize = fontSize.clamped(to: Self.fontSizeRange)
        lineHeight = lineHeight?.clamped(to: Self.lineHeightRange)
    }

    mutating func adjustFontSize(by steps: Int) {
        fontSize += Double(steps) * Self.fontSizeStep
        normalize()
    }

    mutating func reset() {
        self = .default
    }

    var readiumValue: EPUBPreferences {
        EPUBPreferences(
            fontFamily: typeface.readiumValue,
            fontSize: fontSize,
            imageFilter: appearance == .dark ? .darken : nil,
            lineHeight: lineHeight,
            publisherStyles: lineHeight == nil ? nil : false,
            // Lore is a focused reading surface: paragraphs use the full
            // measure of the page instead of inheriting uneven publisher CSS.
            textAlign: .justify,
            theme: appearance.readiumValue
        )
    }
}

@MainActor
protocol ReaderPreferencesStoring: AnyObject {
    func load() -> ReaderPreferences
    func save(_ preferences: ReaderPreferences) throws
}

@MainActor
final class UserDefaultsReaderPreferencesStore: ReaderPreferencesStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "reader.preferences.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> ReaderPreferences {
        guard let data = defaults.data(forKey: key),
              var preferences = try? JSONDecoder().decode(ReaderPreferences.self, from: data)
        else { return .default }
        preferences.normalize()
        return preferences
    }

    func save(_ preferences: ReaderPreferences) throws {
        var normalized = preferences
        normalized.normalize()
        defaults.set(try JSONEncoder().encode(normalized), forKey: key)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
