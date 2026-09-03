import Foundation
import PuzzleKit

/// Deterministische Kürzungsregeln, geladen aus `Resources/abbreviations.json`.
///
/// Diese Stufe läuft **vor** einem LLM-Kürzungslauf, weil sie reproduzierbar,
/// prüfbar und für den größten Teil der Fälle ausreichend ist. Das LLM räumt
/// nur auf, was danach noch zu lang ist.
public struct AbbreviationTable: Sendable {
    public let version: Int
    public let rules: [(String, String)]

    public init(version: Int, rules: [(String, String)]) {
        self.version = version
        self.rules = rules
    }

    public static func load(path: String) throws -> AbbreviationTable {
        struct File: Decodable { let version: Int; let rules: [[String]] }
        let f = try JSONDecoder().decode(File.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        return AbbreviationTable(version: f.version,
                                 rules: f.rules.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil })
    }

    /// Wendet die Regeln an — aber nur an **Wortgrenzen**, und flektierte
    /// Endungen werden mitverbraucht.
    ///
    /// Naives `replacingOccurrences` produziert „amerik.n" aus
    /// „amerikanischen": die Regel trifft „amerikanische", das flektierende „n"
    /// bleibt als Wortrest stehen. Der Fehler fiel erst am echten Katalog auf.
    public func apply(_ s: String) -> String {
        var out = s
        for (from, to) in rules { out = Self.replaceAtWordBoundaries(in: out, from, with: to) }
        return out
    }

    /// Flexionsendungen, die nach einem Treffer noch mit verbraucht werden.
    /// Längste zuerst, damit „en" nicht als „e" + Rest gelesen wird.
    static let inflections = ["ens", "ern", "en", "es", "er", "em", "e", "n", "r", "s", "m"]

    static func isWordChar(_ c: Character) -> Bool { c.isLetter || c == "-" }

    static func replaceAtWordBoundaries(in text: String, _ from: String,
                                        with to: String) -> String {
        guard !from.isEmpty else { return text }
        let chars = Array(text)
        let pat = Array(from)
        var out = ""
        var i = 0
        while i < chars.count {
            let atWordStart = i == 0 || !isWordChar(chars[i - 1])
            if atWordStart, i + pat.count <= chars.count,
               Array(chars[i ..< i + pat.count]) == pat {
                var end = i + pat.count
                // Flexionsendung mitnehmen, damit kein Wortrest übrig bleibt.
                for suffix in inflections {
                    let sc = Array(suffix)
                    if end + sc.count <= chars.count, Array(chars[end ..< end + sc.count]) == sc {
                        let after = end + sc.count
                        if after >= chars.count || !isWordChar(chars[after]) {
                            end = after; break
                        }
                    }
                }
                // Nur ersetzen, wenn hier wirklich ein Wort endet.
                if end >= chars.count || !isWordChar(chars[end]) {
                    out += to
                    i = end
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }
}

public enum Rejection: String, Sendable, CaseIterable, Error {
    case multiWord, hasHyphen, hasParen, hasDigit, badCharacters
    case tooShort, tooLong, noDescription, descriptionTooLong
    case answerAppearsInClue, clueTooShort, ambiguousClue, blocked
}

public struct AnswerCandidate: Sendable {
    public let surface: String
    public let letters: [Letter]
    public let flags: AnswerFlags
    public let zipf: Double
    public let topics: [String]
    public let sourceRef: String
}

/// Titel → Gitterantwort. Der größte Teil der Wikipedia-Titel scheitert hier,
/// und das ist gut: Mehrwortlemmata, Klammerzusätze und Fremdschriftzeichen
/// gehören nicht in ein Kreuzworträtsel.
public enum TitleNormalizer {
    static let blocklist: Set<String> = [
        // Platzhalter: in der Auslieferung eine gepflegte Liste. Bewusst klein
        // gehalten, statt zu tun, als wäre sie vollständig.
        "HITLER", "NSDAP", "SS", "GESTAPO",
    ]

    public static func normalize(title: String) -> Result<(surface: String, letters: [Letter]), Rejection> {
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.contains("(") || t.contains(")") { return .failure(.hasParen) }
        if t.contains(" ") || t.contains("\u{00A0}") { return .failure(.multiWord) }
        if t.contains("-") || t.contains("–") || t.contains("/") || t.contains(".")
            || t.contains(",") || t.contains("'") || t.contains("\u{2019}") {
            return .failure(.hasHyphen)
        }
        if t.contains(where: \.isNumber) { return .failure(.hasDigit) }
        guard let letters = Alphabet.normalize(t) else { return .failure(.badCharacters) }
        if letters.count < 3 { return .failure(.tooShort) }
        if letters.count > 15 { return .failure(.tooLong) }
        let surface = Alphabet.string(letters)
        if blocklist.contains(surface) { return .failure(.blocked) }
        return .success((surface, letters))
    }

    /// Ist der Originaltitel eine Abkürzung? (NATO, USA — durchgehend groß.)
    public static func looksLikeAbbreviation(_ title: String) -> Bool {
        let letters = title.filter(\.isLetter)
        return letters.count >= 2 && letters.count <= 6
            && letters.allSatisfy { $0.isUppercase }
    }

    /// Marker, die in einer Wikidata-Beschreibung auf einen Eigennamen deuten.
    ///
    /// Im Deutschen sind **alle** Substantive großgeschrieben, Großschreibung
    /// taugt also nicht zur Unterscheidung. Deshalb wird die Beschreibung
    /// befragt, nicht der Titel. Die Liste ist eine Heuristik; sie irrt in
    /// Richtung „Eigenname", und das ist die sichere Richtung — Eigennamen
    /// werden nur seltener eingesetzt, nicht ausgeschlossen.
    static let properNounMarkers: [String] = [
        "gemeinde", "stadt in", "ortschaft", "dorf", "landkreis", "provinz",
        "region in", "hauptstadt", "verwaltungseinheit", "ort in", "bezirk",
        "politiker", "schauspieler", "sänger", "musiker", "fußballspieler",
        "sportler", "autor", "schriftsteller", "regisseur", "unternehmer",
        "wissenschaftler", "philosoph", "maler", "komponist", "adliger",
        "familienname", "vorname", "personenname",
        "fluss in", "berg in", "see in", "gebirge in", "insel in", "gewässer in",
        "film", "fernsehserie", "album", "lied", "musikgruppe", "band aus",
        "roman", "computerspiel", "videospiel", "zeitschrift", "zeitung",
        "unternehmen", "marke", "konzern", "organisation", "verein",
        "deutscher ", "deutsche ", "österreichischer ", "schweizer ",
        "us-amerikanisch", "britischer ", "französischer ", "italienischer ",
        "russischer ", "niederländischer ", "spanischer ", "polnischer ",
    ]

    public static func looksLikeProperNoun(description: String?, zipf: Double,
                                           hasEverydayCategory: Bool) -> Bool {
        if let d = description?.lowercased() {
            for m in properNounMarkers where d.contains(m) { return true }
        }
        // Unkategorisiert *und* selten: mit hoher Wahrscheinlichkeit eine
        // konkrete Entität, die nur über die Aufruf-Charts hereinkam.
        return !hasEverydayCategory && zipf < 4.0
    }
}

/// Beschreibung → Fragetext (lang) und Kurzform (für Fragezellen).
public struct ClueNormalizer: Sendable {
    public let abbreviations: AbbreviationTable
    public let widths: GlyphWidthTable
    public let maxLongLength: Int
    public let singleBudget: Int

    public init(abbreviations: AbbreviationTable, widths: GlyphWidthTable,
                maxLongLength: Int = 90, singleBudget: Int = 14_000) {
        self.abbreviations = abbreviations
        self.widths = widths
        self.maxLongLength = maxLongLength
        self.singleBudget = singleBudget
    }

    static func collapse(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripParentheticals(_ s: String) -> String {
        var out = "", depth = 0
        for ch in s {
            if ch == "(" { depth += 1; continue }
            if ch == ")" { depth = max(0, depth - 1); continue }
            if depth == 0 { out.append(ch) }
        }
        return collapse(out)
    }

    /// Wörter, an denen eine Wiktionary-Kontextangabe erkennbar ist.
    ///
    /// Der erste Anlauf prüfte auf **Abwesenheit** von Präpositionen und
    /// Artikeln — nach dem Gedanken, eine Kontextangabe sei eine nackte
    /// Bezeichnung. Das griff daneben: „Meist im Plural:" enthält „im" und blieb
    /// deshalb stehen, 167 Clues trugen so eine Grammatikangabe als Frage.
    /// Umgekehrt ist es verlässlich, denn das Vokabular dieser Angaben ist
    /// geschlossen — und ein Doppelpunkt in einer echten Definition („Gerät zur
    /// Messung des Luftdrucks: es zeigt …") enthält keines dieser Wörter.
    static let contextMarkerWords: Set<String> = [
        "plural", "singular", "mehrzahl", "einzahl", "meist", "meistens", "nur",
        "kein", "keine", "selten", "häufig", "übertragen", "bildlich", "veraltet",
        "veraltend", "gehoben", "umgangssprachlich", "fachsprachlich", "salopp",
        "scherzhaft", "abwertend", "landschaftlich", "regional", "österreichisch",
        "schweizerisch", "norddeutsch", "süddeutsch", "rechtssprache",
        "amtssprache", "jargon", "fachjargon", "seltener", "auch", "zumeist",
    ]

    /// Vorangestellte Kontextangaben aus Wiktionary-Bedeutungen.
    ///
    /// Manche Bedeutungen beginnen mit einer Einordnung und einem Doppelpunkt:
    /// „Rechtssprache; kein Plural: Schutz vor Verfolgung". Der Teil vor dem
    /// Doppelpunkt ist Metainformation, keine Frage — im Rätsel stand
    /// „Rechtssprache; kein Plural: Schutz". Nur ein **kurzes** Präfix wird
    /// entfernt, damit kein echter Doppelpunkt mitten in einer Definition
    /// abgeschnitten wird.
    static func strippingContextPrefix(_ text: String) -> String {
        // Mehrfach, weil Angaben sich stapeln: „Druckereiwesen: kein Plural: …"
        // trug beides, und ein einzelner Durchlauf ließ das zweite stehen.
        var t = text
        for _ in 0 ..< 3 {
            let next = strippingOneContextPrefix(t)
            if next == t { break }
            t = next
        }
        return t
    }

    private static func strippingOneContextPrefix(_ text: String) -> String {
        guard let colon = text.firstIndex(of: ":") else { return text }
        let prefix = text[text.startIndex ..< colon]
        // Reine Länge genügt nicht: „Gerät zur Messung des Luftdrucks:" ist
        // 32 Zeichen kurz und trotzdem die Definition selbst.
        guard prefix.count <= 40 else { return text }
        let words = prefix.split(whereSeparator: { " ,;".contains($0) })
            .map { $0.lowercased() }
        // Entweder eine Grammatikangabe („kein Plural") oder ein einwortiges
        // Fachgebiet („Botanik:", „Druckereiwesen:"). Ein einzelnes Wort vor
        // einem Doppelpunkt ist im Wiktionary durchweg ein Etikett; eine echte
        // Definition davor besteht aus mehreren Wörtern („Gerät zur Messung des
        // Luftdrucks:").
        guard words.contains(where: { contextMarkerWords.contains($0) })
            || words.count == 1 else { return text }
        let rest = collapse(String(text[text.index(after: colon)...]))
        return rest.count >= 8 ? rest : text
    }

    /// Langform: aufräumen, nicht umschreiben. Was zu lang ist, wird an einer
    /// Klausengrenze gekappt — und wenn das nicht reicht, verworfen.
    /// Übriggebliebene Wikitext-Klammern. 33 Clues trugen sie bis in den Katalog
    /// („ABSCHIED — Auch bildlich; Plural selten}}"). Solcher Text ist nicht
    /// gekürzt schlecht, sondern kaputt — er wird verworfen, nicht geflickt.
    /// Wartungsnotizen der Wiktionary-Autoren.
    ///
    /// „QS" heißt Qualitätssicherung und ist ein Hinweis **an die Autoren**, keine
    /// Bedeutung. 191 Clues trugen den Marker bis in den Katalog und ins Rätsel:
    /// „ABBRUCH — Ein Schaden, Beeinträchtigung QS Bedeutungen". Aufgefallen beim
    /// Rendern der Fragenliste in großer Schrift.
    ///
    /// Der Marker steht am Ende, weil die Vorlage im Quelltext hinter der
    /// Bedeutung steht. Entfernt wird deshalb ein Suffix, nicht jedes Vorkommen —
    /// „QS" mitten in einem Satz könnte eine echte Abkürzung sein.
    static let maintenanceMarkers = [
        // Singular und Plural: „GINGER — Person mit roten Haaren QS Bedeutung"
        // blieb beim ersten Anlauf stehen, weil nur die Pluralform in der Liste
        // stand.
        "QS Bedeutungen", "QS Bedeutung", "QS Herkunft", "QS Beispiele",
        "QS Referenzen", "QS Aussprache", "QS Fehlend", "QS Unsicher",
    ]

    static func strippingMaintenanceMarkers(_ text: String) -> String {
        var t = text
        var changed = true
        while changed {
            changed = false
            let trimmed = collapse(t)
            for marker in maintenanceMarkers where trimmed.hasSuffix(marker) {
                t = collapse(String(trimmed.dropLast(marker.count)))
                changed = true
                break
            }
            // Ein Marker kann ein Satzzeichen hinter sich lassen.
            while let last = t.last, last == "," || last == ";" || last == "." {
                t = collapse(String(t.dropLast()))
                changed = true
            }
        }
        return t
    }

    /// Besteht der Text **nur** aus einer Wartungsnotiz?
    ///
    /// Solche Einträge sind keine gekürzte Bedeutung, sondern gar keine:
    /// „HERNEHMEN — QS Bedeutungen (österreichisch) siehe Ref-Duden",
    /// „KUGELKETTE — QS Bedeutungen, siehe Wikipedia". Sie werden verworfen,
    /// nicht beschnitten — vom Marker abzuschneiden bliebe „siehe Wikipedia".
    static func isMaintenanceNote(_ text: String) -> Bool {
        let t = collapse(text)
        return maintenanceMarkers.contains { t.hasPrefix($0) }
    }

    static func hasMarkupRemnants(_ text: String) -> Bool {
        text.contains("{{") || text.contains("}}") || text.contains("[[")
    }

    public func longText(from description: String) -> Result<String, Rejection> {
        guard !Self.hasMarkupRemnants(description) else { return .failure(.clueTooShort) }
        guard !Self.isMaintenanceNote(description) else { return .failure(.clueTooShort) }
        var t = Self.collapse(Self.strippingMaintenanceMarkers(
            Self.strippingContextPrefix(description.replacingOccurrences(of: "\n", with: " "))))
        while t.hasSuffix(".") || t.hasSuffix(";") { t.removeLast() }
        t = Self.collapse(t)
        guard t.count >= 8 else { return .failure(.clueTooShort) }
        if t.count > maxLongLength {
            // An der letzten Klausengrenze vor dem Limit kappen.
            let cutoff = t.index(t.startIndex, offsetBy: maxLongLength)
            let head = t[t.startIndex ..< cutoff]
            if let comma = head.lastIndex(of: ",") {
                t = Self.collapse(String(head[head.startIndex ..< comma]))
            } else if let semi = head.lastIndex(of: ";") {
                t = Self.collapse(String(head[head.startIndex ..< semi]))
            } else {
                return .failure(.descriptionTooLong)
            }
            guard t.count >= 8 else { return .failure(.clueTooShort) }
        }
        // Nach dem Kappen kann ein angefangener Nebensatz stehenbleiben: „Ein
        // Namensbereich, der dazu dient" stand so im Rätsel. Solche Enden werden
        // abgeschnitten, und was danach zu kurz ist, wird verworfen.
        t = Self.trimmingDanglingClause(t)
        guard t.count >= 8 else { return .failure(.clueTooShort) }
        return .success(t.prefix(1).uppercased() + t.dropFirst())
    }

    /// Wörter, die eine Langform nicht beenden dürfen — Relativpronomen,
    /// Bindewörter, Hilfsverben.
    ///
    /// `dient` ist ein Vollverb und fällt hier auf: es stammt aus dem
    /// beobachteten Fall „Ein Namensbereich, der dazu dient" und trägt ihn, weil
    /// das Abwickeln vom Satzende her beginnt. Sauber wäre eine Erkennung
    /// finiter Verben; solange die fehlt, steht hier der Einzelfall — sichtbar
    /// statt versteckt.
    static let clauseOpeners: Set<String> = [
        "der", "die", "das", "dem", "den", "dessen", "deren", "welcher", "welche",
        "welches", "wo", "womit", "worin", "wobei", "wodurch", "wozu",
        "und", "oder", "sowie", "aber", "dass", "weil", "damit", "obwohl",
        "dazu", "dient", "ist", "sind", "war", "waren", "wird", "werden",
        "hat", "haben", "kann", "können", "soll", "sollen",
    ]

    /// Wörter, mit denen ein **Folgesatz** anfängt, der die Definition
    /// fortsetzt statt sie zu wiederholen. Solche Klauseln taugen nicht als
    /// eigenständige Kurzfrage: „ABHEBEN — Z.B. auch einer Unterlage" stand so
    /// im Katalog, aus „Etwas von etwas anderem, zum Beispiel auch einer
    /// Unterlage". Bewusst getrennt von `clauseOpeners`, weil das eine Frage
    /// beantwortet („darf hier anfangen?") und nicht die andere („darf hier
    /// enden?").
    static let continuationStarters: Set<String> = clauseOpeners.union([
        "zum", "zur", "auch", "etwa", "besonders", "insbesondere", "meist",
        "oft", "häufig", "beispielsweise", "ferner", "außerdem", "speziell",
        "allgemein", "übertragen", "kurz", "bes.", "vor", "im", "in", "bei",
        "nach", "mit", "ohne", "von", "vom", "für", "als", "bis", "seit",
        "z.b.", "u.a.", "usw.", "etc.", "sowohl", "entweder", "je",
    ])

    static func trimmingDanglingClause(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        while let last = words.last, clauseOpeners.contains(last.lowercased())
            || last.hasSuffix(",") || last == "-" {
            words.removeLast()
        }
        // Ein zurückgebliebenes Komma am Ende ebenfalls entfernen.
        var result = collapse(words.joined(separator: " "))
        while result.hasSuffix(",") || result.hasSuffix(";") { result.removeLast() }
        return collapse(result)
    }

    public struct Short: Sendable {
        public let text: String
        public let width: Int
        /// Wurde so stark gekürzt, dass das Tier steigen soll?
        public let aggressive: Bool
    }

    /// Mehrere Kurzform-Kandidaten, absteigend nach Güte.
    ///
    /// Warum überhaupt mehrere: 61.990 der 66.428 fehlenden Kurzformen fielen im
    /// Ambiguitätsgatter, nicht bei der Ableitung. Mit nur einem Kandidaten kann
    /// das Gatter bei einer Kollision nur verwerfen; mit mehreren kann es
    /// ausweichen.
    ///
    /// Rang 0 ist die bisherige Kurzform (erste Klausel) — die bleibt die beste,
    /// weil die erste Klausel die eigentliche Definition trägt. Danach kommen die
    /// **späteren Klauseln**, denn im Wiktionary sind das oft Synonyme und damit
    /// spezifischer als eine gekappte erste Klausel: „Tiefergelegenes Gelände
    /// zwischen Erhebungen, Geländeeinschnitt" liefert „Geländeeinschnitt".
    ///
    /// Angehängte **Relativsätze** sind keine Synonyme und werden übersprungen:
    /// „Einmalige Handlung, die etwas Gutes oder Böses bewirkt" darf nicht zu
    /// „Die etwas Gutes oder Böses bewirkt" werden.
    public func shortCandidates(from long: String, limit: Int = 4) -> [Short] {
        var out: [Short] = []
        var seen: Set<String> = []

        func add(_ s: Short?) {
            guard let s, out.count < limit else { return }
            let key = s.text.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(s)
        }

        add(shortText(from: long))

        let clauses = Self.stripParentheticals(long)
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { Self.collapse(String($0)) }
        for clause in clauses.dropFirst() where out.count < limit {
            guard let first = clause.split(separator: " ").first?.lowercased(),
                  !Self.continuationStarters.contains(first) else { continue }
            add(shortText(from: clause))
        }
        return out
    }

    /// Kurzform in eskalierenden Stufen. Jede Stufe wird nur betreten, wenn die
    /// vorige nicht ins Budget passt — abkürzen macht Clues härter zu lesen, also
    /// wird nur abgekürzt, wenn es nötig ist. „Nahrungsmittel" ist besser als
    /// „Nahrungsm.", und wenn beides passt, gewinnt die Langform.
    ///
    ///   1. aufräumen: Klammern weg, erste Klausel, Artikel weg
    ///   2. Abkürzungsregeln anwenden
    ///   3. Wörter von hinten streichen  ← erst hier gilt `aggressive`
    ///
    /// Bleibt nichts Sinnvolles übrig, gibt es keine Kurzform. Kein Rätsel wird
    /// dadurch schlechter; die Antwort steht dann nur nicht für Schwedenrätsel
    /// zur Verfügung.
    public func shortText(from long: String) -> Short? {
        guard !Self.hasMarkupRemnants(long) else { return nil }
        // Auch hier, nicht nur in `longText`: die Kandidaten aus späteren
        // Klauseln kommen an `longText` vorbei, und eine solche Klausel kann die
        // Grammatikangabe tragen („…, zumeist Plural: Dreck").
        var t = Self.stripParentheticals(
            Self.strippingMaintenanceMarkers(Self.strippingContextPrefix(long)))
        // **Eine Kurzfrage enthält keinen Doppelpunkt.** Das Marker-Vokabular
        // nachzutragen war Flickwerk: 1.603 Kurzformen trugen Etiketten, die kein
        // Grammatikwort enthalten („Christliche und jüdische Religion:", „Als
        // Computer:", „Von Stoffen:") — teils mit nichts dahinter. Die Regel gilt
        // nur hier, nicht für Langformen: dort trägt der Rest des Satzes genug,
        // um das Etikett zu verkraften.
        if let colon = t.lastIndex(of: ":") {
            let after = Self.collapse(String(t[t.index(after: colon)...]))
            guard after.count >= 5 else { return nil }
            t = after
        }
        if let comma = t.firstIndex(of: ",") { t = Self.collapse(String(t[t.startIndex ..< comma])) }
        for article in ["Der ", "Die ", "Das ", "Ein ", "Eine ", "der ", "die ", "das "]
        where t.hasPrefix(article) {
            t = String(t.dropFirst(article.count)); break
        }
        t = Self.collapse(t)
        guard !t.isEmpty else { return nil }

        /// Funktionswörter, die am Ende einer gekürzten Frage nichts verloren
        /// haben. „Feine Zucker- und" ist keine Frage, sondern ein Satzanfang.
        let danglers: Set<String> = Set<String>([
            "und", "oder", "sowie", "bzw.", "der", "die", "das", "des", "dem", "den",
            "ein", "eine", "einer", "eines", "einem", "einen",
            "in", "im", "aus", "von", "vom", "mit", "zu", "zur", "zum", "für", "bei",
            "auf", "am", "an", "als", "über", "unter", "durch", "nach", "vor", "um",
            // Nachgetragen aus einem gerenderten Rätsel: „TAL — Tiefergelegenes
            // Gelände zwischen". Diese Regel kostet keinen Pool, weil nur das
            // letzte Wort wegfällt und die Frage danach steht.
            "zwischen", "gegen", "ohne", "seit", "während", "wegen", "trotz",
            "innerhalb", "außerhalb", "entlang", "gegenüber", "neben", "hinter",
            "samt", "statt", "bis", "ab", "je", "pro", "laut", "mittels",
            "ist", "sind", "war", "u.a.", "z.B.", "ca.",
            // Abgekürzte Funktionswörter: „Teil von" wird zu „Teil v.", und das
            // „v." hängt am Ende genauso in der Luft wie das ausgeschriebene Wort.
            // Aus einem gerenderten Fall: „AALBUCH — Im Osten gelegener Teil v."
            "v.", "f.", "d.", "z.", "u.", "bzw", "usw.", "etc.", "u.ä.", "o.ä.",
        ]).union(
            // Datengetrieben: Abkürzungen, die aus **Adjektiven** entstanden
            // sind ("ital.", "amerik.", "franz."), sind Modifikatoren. Am Ende
            // einer gekürzten Frage hängen sie in der Luft — „Eintopfgericht
            // aus der amerik." ist unfertig. Die Regeltabelle weiß selbst,
            // welche das sind: Muster kleingeschrieben, Ersetzung mit Punkt.
            abbreviations.rules
                .filter { $0.0.first?.isLowercase == true && $0.1.hasSuffix(".") }
                .map { $0.1.lowercased() }
        )

        func trimDanglers(_ s: String) -> String {
            var words = s.split(separator: " ").map(String.init)
            while let last = words.last,
                  danglers.contains(last.lowercased())
                      || last.hasSuffix("-") || last == "," || last == "-" {
                words.removeLast()
            }
            return words.joined(separator: " ")
        }

        let sourceWordCount = t.split(separator: " ").count

        func finish(_ raw: String, aggressive: Bool) -> Short? {
            let candidate = trimDanglers(Self.collapse(raw))
            guard !candidate.isEmpty else { return nil }
            let wasCut = candidate.split(separator: " ").count < sourceWordCount
            let text = candidate.prefix(1).uppercased() + candidate.dropFirst()
            // Eine **mehrwortige** Kurzform ohne Substantiv ist eine angefangene
            // Wortgruppe: ERDE hatte „Belebter und dritter" (aus „Belebter und
            // dritter, von der Sonne aus gezählter Planet …"). Im Deutschen ist
            // jedes großgeschriebene Wort ein Substantiv; das erste zählt nicht,
            // weil dort auch ein Adjektiv groß wäre.
            //
            // Bewusst nur mehrwortig. Ob ein einzelnes großgeschriebenes Wort
            // Substantiv („Pflanzenart") oder Adjektivfragment („Belebter") ist,
            // entscheidet die Endung — und jede Endungsregel greift daneben:
            // -er trifft „Lehrer" und „Zucker", -e trifft „Sonne" und „Rose".
            // Ein einzelnes Fragment bleibt deshalb möglich; es ist kurz und
            // harmloser als die Wortgruppe, aus der es kam. Siehe README,
            // Abschnitt „Bekannte Lücken".
            let words = text.split(separator: " ").map(String.init)
            // Eine Kurzform, die nur aus Abkürzungen besteht, sagt nichts:
            // „ACHÄER — Angeh." stand so im Katalog. Ein Punkt am Wortende ist
            // hier verlässlich, weil die Abkürzungstabelle ihn selbst setzt.
            if words.allSatisfy({ $0.hasSuffix(".") }) { return nil }
            // Reine Funktionswörter sind keine Frage: „Welche" stand so im
            // gerenderten Rätsel. Die Listen, die sagen, womit eine Frage nicht
            // enden und nicht anfangen darf, sagen zusammen auch, woraus sie
            // nicht bestehen darf.
            if words.allSatisfy({ danglers.contains($0.lowercased())
                                  || Self.continuationStarters.contains($0.lowercased()) }) {
                return nil
            }
            // Ein einzelnes Wort mit starker Adjektivendung, das aus einer
            // längeren Wortgruppe **herausgeschnitten** wurde, ist ein Fragment:
            // „Flaches", „Beheizbarer", „Obergäriges" standen so im Rätsel. Der
            // Schnitt ist die Bedingung, die den Unterschied macht — „Zucker"
            // und „Sonne" stehen so in der Quelle und bleiben deshalb.
            if words.count == 1, wasCut,
               ["es", "er", "en", "em"].contains(where: { text.lowercased().hasSuffix($0) }) {
                return nil
            }
            if words.count > 1,
               !words.dropFirst().contains(where: { $0.first?.isUppercase == true }) {
                return nil
            }
            guard text.count >= 4 else { return nil }
            let w = widths.width(of: text)
            guard w <= singleBudget else { return nil }
            return Short(text: text, width: w, aggressive: aggressive)
        }

        // Stufe 1: unverändert, wenn es passt.
        if let s = finish(t, aggressive: false) { return s }
        // Stufe 2: abkürzen.
        let abbreviated = Self.collapse(abbreviations.apply(t))
        if let s = finish(abbreviated, aggressive: false) { return s }
        // Stufe 3: an einer Phrasengrenze schneiden.
        //
        // Wort-für-Wort von hinten zu kürzen landet mitten in einer
        // Präpositionalphrase — „Pflanzenart aus der Gatt." ist unfertig. Der
        // saubere Schnitt liegt **vor** der Präposition: „Pflanzenart".
        let prepositions: Set<String> = [
            "aus", "in", "im", "von", "vom", "mit", "zu", "zur", "zum", "für",
            "bei", "auf", "an", "am", "über", "unter", "durch", "nach", "vor",
            "um", "gegen", "ohne", "innerhalb", "während", "wegen", "seit",
        ]
        var words = abbreviated.split(separator: " ").map(String.init)
        let cuts = words.indices.filter { prepositions.contains(words[$0].lowercased()) }
        for cut in cuts.reversed() where cut > 0 {
            if let s = finish(words[0 ..< cut].joined(separator: " "), aggressive: true) {
                return s
            }
        }
        // Stufe 4: notfalls doch von hinten kürzen.
        while words.count > 1 {
            words.removeLast()
            if let s = finish(words.joined(separator: " "), aggressive: true) { return s }
        }
        return nil
    }

    /// Entfernt das führende Lemma aus einem Artikel-Extrakt.
    ///
    /// Deutsche Wikipedia-Artikel beginnen praktisch immer mit dem Stichwort
    /// („Abdounodus ist eine ausgestorbene Gattung …"). Ungefiltert scheitert
    /// deshalb *jeder* Extrakt am Leak-Gatter — im ersten Lauf überlebte 1 von
    /// 206. Nach dem Abschneiden von Lemma und Kopula bleibt eine brauchbare
    /// Definition übrig.
    public static func stripLeadingLemma(_ text: String, title: String) -> String {
        var t = collapse(text)
        let lowerTitle = title.lowercased()

        // Optionaler Artikel vor dem Lemma: „Der Ahorn ist …"
        for article in ["Der ", "Die ", "Das "] where t.hasPrefix(article) {
            let rest = String(t.dropFirst(article.count))
            if rest.lowercased().hasPrefix(lowerTitle) { t = rest }
            break
        }
        if t.lowercased().hasPrefix(lowerTitle) {
            t = collapse(String(t.dropFirst(title.count)))
        }
        // Kopula und Anschlussfloskeln abschneiden, längste Muster zuerst.
        let copulas = [
            "ist eine", "ist ein", "ist der", "ist die", "ist das",
            "sind eine", "sind ein", "sind", "war eine", "war ein", "waren",
            "bezeichnet eine", "bezeichnet ein", "bezeichnet", "steht für",
            "bildet eine", "bildet ein", "meint", "heißt",
        ]
        for c in copulas where t.lowercased().hasPrefix(c) {
            t = collapse(String(t.dropFirst(c.count)))
            break
        }
        // Restliche Satzzeichen am Anfang.
        while let f = t.first, f == "," || f == ":" || f == "-" || f == "–" {
            t = collapse(String(t.dropFirst()))
        }
        guard !t.isEmpty else { return "" }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Enthält der Clue seine eigene Antwort? Der Stamm ab 5 Zeichen zählt mit,
    /// damit „Brotsorte" als Frage zu BROT auffällt.
    public static func clueLeaksAnswer(clue: String, answerSurface: String) -> Bool {
        let c = clue.lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
        let a = answerSurface.lowercased()
        if a.count >= 3, c.contains(a) { return true }
        if a.count >= 6 {
            let stem = String(a.prefix(max(5, a.count - 2)))
            if c.contains(stem) { return true }
        }
        return false
    }
}
