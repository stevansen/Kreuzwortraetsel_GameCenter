/// Ein Rätsel als Verweis: `kreuzwort://p/<variante>/<stufe>/<seed>`.
///
/// **Warum das geht.** Ein Rätsel ist vollständig durch
/// `(seed, variant, difficulty, generatorVersion, catalogVersion)` beschrieben,
/// weil der Generator deterministisch ist. „Schick mir dieses Rätsel" ist damit
/// ein Link und kein Datentransfer — rund 40 Zeichen statt eines Gitters mit
/// Fragen.
///
/// Der Parser ist von Hand geschrieben statt über `URL`: `PuzzleKit` importiert
/// kein Foundation, und ein Link besteht ohnehin nur aus Schrägstrichen.
public struct PuzzleLink: Sendable, Hashable {
    public static let scheme = "kreuzwort"
    public static let host = "kreuzwort.app"
    public static let path = "p"

    public let seed: UInt64
    public let variant: PuzzleVariant
    public let difficulty: Difficulty
    /// Versionen sind optional: fehlen sie, gilt die aktuelle. Ein Link soll
    /// nicht brechen, nur weil der Katalog gewachsen ist — er zeigt dann eben
    /// auf das Rätsel, das *heute* aus diesem Seed entsteht.
    public let generatorVersion: Int?
    public let catalogVersion: Int?

    public init(seed: UInt64, variant: PuzzleVariant, difficulty: Difficulty,
                generatorVersion: Int? = nil, catalogVersion: Int? = nil) {
        self.seed = seed
        self.variant = variant
        self.difficulty = difficulty
        self.generatorVersion = generatorVersion
        self.catalogVersion = catalogVersion
    }

    public init(puzzle: Puzzle, pinVersions: Bool = false) {
        self.init(seed: puzzle.seed, variant: puzzle.variant, difficulty: puzzle.difficulty,
                  generatorVersion: pinVersions ? puzzle.generatorVersion : nil,
                  catalogVersion: pinVersions ? puzzle.catalogVersion : nil)
    }

    // MARK: - Schreiben

    /// Eigenes Schema, für Verweise innerhalb des Geräts.
    public var customURLString: String {
        "\(Self.scheme)://\(Self.path)/\(tail)"
    }

    /// Universal Link, für Verweise, die auch ohne installierte App etwas anzeigen.
    public var universalURLString: String {
        "https://\(Self.host)/\(Self.path)/\(tail)"
    }

    private var tail: String {
        var out = "\(variant.rawValue)/\(difficulty.rawValue)/\(seed)"
        if let generatorVersion, let catalogVersion {
            out += "?g=\(generatorVersion)&c=\(catalogVersion)"
        }
        return out
    }

    // MARK: - Lesen

    public enum ParseError: Error, Sendable, Equatable {
        case notAPuzzleLink
        case unknownVariant(String)
        case unknownDifficulty(String)
        case badSeed(String)
    }

    /// Nimmt beide Formen und ist bei Kleinigkeiten nachsichtig: ein
    /// abschließender Schrägstrich, Groß- und Kleinschreibung im Schema.
    ///
    /// Nachsichtig heißt **nicht** ratend: eine unbekannte Variante wird als
    /// Fehler gemeldet und nicht stillschweigend auf `classic` gesetzt. Sonst
    /// öffnet ein Tippfehler im Link das falsche Rätsel.
    public static func parse(_ string: String) throws -> PuzzleLink {
        var rest = string.trimmingWhitespace()
        let lower = rest.lowercased()

        if lower.hasPrefix("\(scheme)://") {
            rest = String(rest.dropFirst(scheme.count + 3))
        } else if lower.hasPrefix("https://\(host)/") {
            rest = String(rest.dropFirst("https://\(host)/".count))
        } else if lower.hasPrefix("http://\(host)/") {
            rest = String(rest.dropFirst("http://\(host)/".count))
        } else {
            throw ParseError.notAPuzzleLink
        }

        var query = ""
        if let mark = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: mark)...])
            rest = String(rest[..<mark])
        }
        while rest.hasSuffix("/") { rest = String(rest.dropLast()) }

        let parts = rest.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0].lowercased() == path else {
            throw ParseError.notAPuzzleLink
        }
        guard let variant = PuzzleVariant(rawValue: parts[1].lowercased()) else {
            throw ParseError.unknownVariant(parts[1])
        }
        guard let difficulty = Difficulty(rawValue: parts[2].lowercased()) else {
            throw ParseError.unknownDifficulty(parts[2])
        }
        guard let seed = UInt64(parts[3]) else {
            throw ParseError.badSeed(parts[3])
        }

        var generatorVersion: Int?
        var catalogVersion: Int?
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            if kv[0] == "g" { generatorVersion = Int(kv[1]) }
            if kv[0] == "c" { catalogVersion = Int(kv[1]) }
        }

        return PuzzleLink(seed: seed, variant: variant, difficulty: difficulty,
                          generatorVersion: generatorVersion, catalogVersion: catalogVersion)
    }

    /// Schlüssel-Wert-Paare für `NSUserActivity` (Handoff).
    ///
    /// Handoff ist der schnelle Pfad, CloudKit der verlässliche: das Rätsel auf
    /// dem iPad weiterzuspielen soll nicht auf eine Synchronisierung warten.
    public var activityPayload: [String: String] {
        var out = ["variant": variant.rawValue,
                   "difficulty": difficulty.rawValue,
                   "seed": String(seed)]
        if let generatorVersion { out["g"] = String(generatorVersion) }
        if let catalogVersion { out["c"] = String(catalogVersion) }
        return out
    }

    public init?(activityPayload payload: [String: String]) {
        guard let variantRaw = payload["variant"],
              let variant = PuzzleVariant(rawValue: variantRaw),
              let difficultyRaw = payload["difficulty"],
              let difficulty = Difficulty(rawValue: difficultyRaw),
              let seedRaw = payload["seed"], let seed = UInt64(seedRaw)
        else { return nil }
        self.init(seed: seed, variant: variant, difficulty: difficulty,
                  generatorVersion: payload["g"].flatMap(Int.init),
                  catalogVersion: payload["c"].flatMap(Int.init))
    }
}

extension String {
    /// Ohne Foundation: `trimmingCharacters(in:)` gibt es hier nicht.
    func trimmingWhitespace() -> String {
        var chars = Array(self)
        while let first = chars.first, first == " " || first == "\n" || first == "\t" {
            chars.removeFirst()
        }
        while let last = chars.last, last == " " || last == "\n" || last == "\t" {
            chars.removeLast()
        }
        return String(chars)
    }
}
