import Foundation
import SwiftUI
import PuzzleKit

/// Zugriff auf die Oberflächentexte.
///
/// **Warum das hier liegt und nicht im Kern.** `PuzzleKit` importiert kein
/// Foundation und kann deshalb nicht lokalisieren. Anzeigetexte gehören
/// ohnehin in die Oberflächenschicht: der Kern liefert Strukturen
/// (`PuzzleVariant`, `ScoreBreakdown.Line.Kind`), diese Schicht die Sprache.
/// Vorher standen deutsche Literale im Kern, was die App auf eine Sprache
/// festgenagelt hätte.
///
/// **Was lokalisiert ist und was nicht.** Die Oberfläche gibt es in Deutsch,
/// Englisch und Italienisch. Der **Rätselinhalt** bleibt deutsch: der
/// Fragenkatalog stammt aus deutschem Wiktionary, Wikidata und deutschen
/// Korpora. Eine italienische oder englische Fassung der Rätsel wäre ein
/// eigener Katalog — dieselbe Arbeit wie M2 noch einmal, pro Sprache.
public enum Loc {
    /// Erzwungene Sprache, unabhängig von der Systemsprache.
    ///
    /// Zwei Gründe: erstens will man sich alle drei Fassungen ansehen können
    /// (`uishot --lang it`), zweitens ist eine App-eigene Sprachwahl in Südtirol
    /// keine Spielerei — Systemsprache und gewünschte Oberflächensprache fallen
    /// dort regelmäßig auseinander.
    ///
    /// Der naheliegende Weg über `UserDefaults`/`AppleLanguages` funktioniert
    /// nicht verlässlich: Foundation löst die Sprachliste früher auf, als ein
    /// Programm sie setzen kann. Deshalb wird das passende `.lproj`-Bundle direkt
    /// aufgelöst.
    nonisolated(unsafe) public static var forcedLanguage: String?

    /// Verfügbare Oberflächensprachen, ohne die Rückfallsprache doppelt zu nennen.
    public static var availableLanguages: [String] {
        Bundle.module.localizations.filter { $0 != "Base" }.sorted()
    }

    static var bundle: Bundle {
        guard let language = forcedLanguage,
              let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path)
        else { return .module }
        return localized
    }

    /// Für `Text`: SwiftUI löst den Schlüssel gegen das Bundle auf.
    public static func key(_ key: String) -> LocalizedStringKey { LocalizedStringKey(key) }

    /// Für alles, was einen `String` braucht — vor allem
    /// Barrierefreiheits-Beschriftungen, die keine `Text`-Ansicht sind.
    public static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    public static func string(_ key: String, _ args: any CVarArg...) -> String {
        let locale = forcedLanguage.map { Locale(identifier: $0) } ?? .current
        return String(format: string(key), locale: locale, arguments: args)
    }
}

public extension Text {
    /// `Text(loc: "action.check")` — kürzer als der Bundle-Durchgriff an jeder Stelle.
    init(loc key: String) { self.init(Loc.key(key), bundle: Loc.bundle) }
}

// MARK: - Anzeigenamen für Kern-Typen

public extension PuzzleVariant {
    var displayName: String { Loc.string("variant.\(rawValue)") }
}

public extension Difficulty {
    var displayName: String { Loc.string("difficulty.\(rawValue)") }
}

public extension Direction {
    var displayName: String {
        Loc.string(self == .across ? "direction.across" : "direction.down")
    }
}

public extension ScoreBreakdown.Line.Kind {
    var displayName: String {
        switch self {
        case .base: Loc.string("score.base")
        case .size: Loc.string("score.size")
        case .time: Loc.string("score.time")
        case .timeWithoutBonus: Loc.string("score.timeWithoutBonus")
        case .clean: Loc.string("score.clean")
        case .streak: Loc.string("score.streak")
        case .daily: Loc.string("score.daily")
        case .hints: Loc.string("score.hints")
        case .total: Loc.string("score.total")
        }
    }

    /// Die Summenzeile wird hervorgehoben.
    var isTotal: Bool { self == .total }
}
