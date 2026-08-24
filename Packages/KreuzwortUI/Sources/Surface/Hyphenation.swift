import Foundation

/// Weiche Trennstellen in Fragen für Schwedenrätsel-Zellen.
///
/// **Das Problem, gemessen.** Der Breiten-Etat einer Doppelzelle ist 9.500
/// Tausendstel-Em und erlaubt zwei Zeilen — also 4,75 Em je Zeile, bei
/// deutschem Text etwa neun Zeichen. „Möbelstück" hat zehn, und SwiftUI brach
/// es ohne Trennstrich mitten im Wort: im gerenderten Rätsel stand
/// „Möbelstü ck", „Flüssigkei t", „Sprechweis e".
///
/// **Warum nicht filtern.** Ein hartes Kriterium „längstes Wort passt in eine
/// Zeile" würde rund 90 % des Doppelzellen-Pools verwerfen — deutsche
/// Substantive sind länger als neun Zeichen. Die Zelle ist zu schmal für die
/// Sprache, nicht der Katalog zu schlecht.
///
/// **Was stattdessen.** Deutsche Leser erwarten „Möbel-stück". Die Trennstellen
/// kommen von `CFStringGetHyphenationLocationBeforeIndex` — also aus den
/// Sprachdaten des Systems, nicht aus selbstgebauten Regeln. Eingefügt wird ein
/// weiches Trennzeichen (U+00AD): sichtbar nur dort, wo tatsächlich umbrochen
/// wird, und ohne die Textbreite an anderen Stellen zu verändern.
public enum Hyphenation {
    /// Weiches Trennzeichen. Wird nur gezeichnet, wenn an der Stelle umbrochen
    /// wird — deshalb darf es großzügig gesetzt werden.
    static let soft: Character = "\u{00AD}"

    /// Ab dieser Wortlänge lohnt Trennen. Kürzere Wörter passen in jede Zeile,
    /// und ein Trennstrich in „Stadt" wäre nur Unruhe.
    static let minimumWordLength = 9

    /// Kein Wortteil kürzer als das. „E-lefant" ist korrekt getrennt und liest
    /// sich trotzdem schlecht.
    static let minimumFragment = 3

    /// Cache: dieselbe Frage wird bei jedem Neuzeichnen des Gitters gebraucht,
    /// und die Trennung kostet einen Aufruf ins System je Position.
    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private var entries: [String: String] = [:]
        private let lock = NSLock()

        func value(for key: String, build: (String) -> String) -> String {
            lock.withLock {
                if let hit = entries[key] { return hit }
                let made = build(key)
                // Ein Rätsel hat höchstens ein paar Dutzend Fragen; die Grenze
                // ist nur ein Riegel gegen unbegrenztes Wachsen über viele
                // Rätsel hinweg.
                if entries.count > 4_000 { entries.removeAll() }
                entries[key] = made
                return made
            }
        }
    }

    /// Setzt weiche Trennstellen in alle Wörter, die lang genug sind.
    ///
    /// Ohne verfügbare Trenndaten für die Sprache bleibt der Text unverändert —
    /// dann bricht SwiftUI wie vorher, was schlechter aussieht, aber nichts
    /// kaputt macht.
    public static func hyphenated(_ text: String, locale: Locale = .current) -> String {
        cache.value(for: "\(locale.identifier)|\(text)") { _ in
            build(text, locale: locale)
        }
    }

    private static func build(_ text: String, locale: Locale) -> String {
        let cfLocale = locale as CFLocale
        guard CFStringIsHyphenationAvailableForLocale(cfLocale) else { return text }
        return text.split(separator: " ", omittingEmptySubsequences: false)
            .map { word in
                word.count >= minimumWordLength
                    ? hyphenate(String(word), locale: cfLocale)
                    : String(word)
            }
            .joined(separator: " ")
    }

    private static func hyphenate(_ word: String, locale: CFLocale) -> String {
        let utf16 = Array(word.utf16)
        var positions: [Int] = []
        // Von hinten nach vorne fragen: die API nennt die Trennstelle **vor**
        // einem Index, also liefert ein Rückwärtslauf alle Stellen.
        var index = utf16.count
        while index > minimumFragment {
            let location = CFStringGetHyphenationLocationBeforeIndex(
                word as CFString, index,
                CFRangeMake(0, utf16.count), 0, locale, nil)
            guard location != kCFNotFound, location > 0 else { break }
            if location >= minimumFragment,
               utf16.count - location >= minimumFragment {
                positions.append(location)
            }
            index = location
        }
        guard !positions.isEmpty else { return word }

        var out = ""
        let breaks = Set(positions)
        for (offset, unit) in utf16.enumerated() {
            if breaks.contains(offset) { out.append(soft) }
            out.append(Character(UnicodeScalar(unit) ?? " "))
        }
        return out
    }
}
