/// Geprüfte Seeds, zur **Bauzeit** ermittelt.
///
/// Warum es das gibt: die Erzeugung gelingt nicht bei jedem Seed. Gemessen über
/// 8 Kombinationen × 3 Seeds kamen 21 von 24 durch, und die harten Stufen
/// brauchen dabei Sekunden bis Minuten — classic/experte zwischen 6 s und 8 min,
/// wobei die 8 min der **Fehlschlag** sind. Für ein Tagesrätsel, dessen Seed das
/// Datum ist, hieße das: an manchen Tagen kein Rätsel, und an anderen Minuten
/// Wartezeit. Beides ist auf einem Telefon nicht zumutbar.
///
/// Die Lösung tastet das Seed-Versprechen nicht an. Ein Rätsel ist weiterhin
/// vollständig durch `(seed, variante, stufe, generatorVersion, catalogVersion)`
/// beschrieben — nur die **Wahl** des Seeds passiert nicht mehr blind, sondern
/// aus einer Liste, für die zur Bauzeit nachgewiesen wurde, dass sie erzeugbar
/// ist. Geteilte Links, Spielstände und Handoff bleiben unverändert gültig.
///
/// Die Liste ist an Generator- und Katalogversion gebunden: ein Seed, der mit
/// einem anderen Katalog geprüft wurde, sagt nichts. Passt die Version nicht,
/// gilt die Liste als nicht vorhanden — dann fällt die App auf die alte,
/// blinde Wahl zurück, statt falsche Zusagen zu machen.
public struct VerifiedSeeds: Sendable, Equatable {
    public let generatorVersion: Int
    public let catalogVersion: Int
    /// Schlüssel ist `"<variante>|<stufe>"`. Kein Dictionary über Enums, weil
    /// über Dictionaries im Generatorpfad nicht iteriert werden darf — hier wird
    /// nur nachgeschlagen, und die Reihenfolge geht nirgends ein.
    private let table: [String: [UInt64]]

    public init(generatorVersion: Int, catalogVersion: Int,
                table: [String: [UInt64]]) {
        self.generatorVersion = generatorVersion
        self.catalogVersion = catalogVersion
        self.table = table
    }

    static func key(_ variant: PuzzleVariant, _ difficulty: Difficulty) -> String {
        "\(variant.rawValue)|\(difficulty.rawValue)"
    }

    public func seeds(_ variant: PuzzleVariant, _ difficulty: Difficulty) -> [UInt64] {
        table[Self.key(variant, difficulty)] ?? []
    }

    /// Fehlt für irgendeine Kombination ein Seed, ist die Liste unbrauchbar —
    /// eine halbe Zusage ist schlimmer als keine.
    public var isComplete: Bool {
        for v in PuzzleVariant.allCases {
            for d in Difficulty.allCases where seeds(v, d).isEmpty { return false }
        }
        return true
    }

    /// Der Seed des Tagesrätsels: weltweit identisch, serverlos, und erzeugbar.
    ///
    /// Gewählt wird über denselben Hash wie vorher, nur als **Index** in die
    /// geprüfte Liste statt als Seed selbst. Damit bleibt das Tagesrätsel eine
    /// Funktion des Datums allein.
    public func dailySeed(isoDate: String, variant: PuzzleVariant,
                          difficulty: Difficulty) -> UInt64? {
        let list = seeds(variant, difficulty)
        guard !list.isEmpty else { return nil }
        let h = SHA256.seed("daily|\(isoDate)|\(variant.rawValue)|\(difficulty.rawValue)")
        return list[Int(h % UInt64(list.count))]
    }

    /// Ein Seed für ein freies Spiel. `pick` kommt von außen (Uhr, Zufall) und
    /// wird nur als Index verwendet, damit die Wahl beliebig sein darf, das
    /// Ergebnis aber immer erzeugbar ist.
    public func seed(variant: PuzzleVariant, difficulty: Difficulty,
                     pick: UInt64) -> UInt64? {
        let list = seeds(variant, difficulty)
        guard !list.isEmpty else { return nil }
        return list[Int(pick % UInt64(list.count))]
    }

    public var count: Int { table.values.reduce(0) { $0 + $1.count } }
}

// MARK: - Textformat

/// Zeilenformat statt JSON, weil `PuzzleKit` kein Foundation importiert (und ein
/// Seam-Scan das prüft). Eine Zeile je Kombination, Zahlen mit Leerzeichen
/// getrennt:
///
/// ```
/// kwseeds 1
/// generator 3
/// catalog 2
/// classic leicht 1 4 9 17
/// arrow experte 2 5 8
/// ```
///
/// Unbekannte Schlüsselzeilen werden übersprungen, damit eine spätere Erweiterung
/// alte Leser nicht zerbricht. Alles andere ist streng: eine unparsbare Zahl
/// verwirft die Datei, statt still einen Teil zu laden.
extension VerifiedSeeds {
    public enum ParseError: Error, Equatable {
        case missingHeader
        case unsupportedFormat(Int)
        case missingVersions
        case badNumber(String)
        case unknownVariant(String)
        case unknownDifficulty(String)
        case duplicateCombination(String)
    }

    public static let formatVersion = 1

    public static func parse(_ text: String) throws -> VerifiedSeeds {
        var format: Int?
        var generator: Int?
        var catalog: Int?
        var table: [String: [UInt64]] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmed()
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)
            guard let head = fields.first else { continue }

            switch head {
            case "kwseeds":
                guard fields.count == 2, let v = Int(fields[1]) else {
                    throw ParseError.missingHeader
                }
                guard v == formatVersion else { throw ParseError.unsupportedFormat(v) }
                format = v
            case "generator":
                guard fields.count == 2, let v = Int(fields[1]) else {
                    throw ParseError.badNumber(line)
                }
                generator = v
            case "catalog":
                guard fields.count == 2, let v = Int(fields[1]) else {
                    throw ParseError.badNumber(line)
                }
                catalog = v
            default:
                guard let variant = PuzzleVariant(rawValue: head) else {
                    // Kein Fehler: eine unbekannte Schlüsselzeile darf hinzukommen.
                    continue
                }
                guard fields.count >= 2 else { throw ParseError.badNumber(line) }
                guard let difficulty = Difficulty(rawValue: fields[1]) else {
                    throw ParseError.unknownDifficulty(fields[1])
                }
                let key = Self.key(variant, difficulty)
                guard table[key] == nil else { throw ParseError.duplicateCombination(key) }
                var seeds: [UInt64] = []
                for field in fields.dropFirst(2) {
                    guard let s = UInt64(field) else { throw ParseError.badNumber(field) }
                    seeds.append(s)
                }
                table[key] = seeds
            }
        }

        guard format != nil else { throw ParseError.missingHeader }
        guard let generator, let catalog else { throw ParseError.missingVersions }
        return VerifiedSeeds(generatorVersion: generator, catalogVersion: catalog,
                             table: table)
    }

    /// Serialisierung in derselben Reihenfolge wie `allCases` — die Datei ist
    /// damit reproduzierbar und im Diff lesbar.
    public func serialized() -> String {
        var out = "kwseeds \(Self.formatVersion)\n"
        out += "generator \(generatorVersion)\n"
        out += "catalog \(catalogVersion)\n"
        for v in PuzzleVariant.allCases {
            for d in Difficulty.allCases {
                let list = seeds(v, d)
                guard !list.isEmpty else { continue }
                out += "\(v.rawValue) \(d.rawValue) "
                    + list.map { "\($0)" }.joined(separator: " ") + "\n"
            }
        }
        return out
    }
}

extension StringProtocol {
    /// Ohne Foundation gibt es kein `trimmingCharacters`.
    func trimmed() -> String {
        var s = Substring(self)
        while let f = s.first, f == " " || f == "\t" || f == "\r" { s = s.dropFirst() }
        while let l = s.last, l == " " || l == "\t" || l == "\r" { s = s.dropLast() }
        return String(s)
    }
}
