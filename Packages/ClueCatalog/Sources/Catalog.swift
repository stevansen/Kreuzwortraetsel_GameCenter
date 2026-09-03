import Foundation
import PuzzleKit

public enum ClueKind: Int, Codable, Sendable, CaseIterable {
    case definition = 0, synonym = 1, fillInBlank = 2, trivia = 3, wordplay = 4
    public var label: String {
        switch self {
        case .definition: "Definition"
        case .synonym: "Synonym"
        case .fillInBlank: "Lücke"
        case .trivia: "Wissen"
        case .wordplay: "Wortspiel"
        }
    }
}

public struct CatalogAnswer: Sendable {
    public var id: Int32 = 0
    public var surface: String
    public var zipf: Double
    public var flags: AnswerFlags
    public var topics: [String]
    /// Wortart aus dem Wiktionary (`noun`, `verb`, `adjective`, …), leer wenn
    /// unbekannt. Wird gebraucht, um Frage und Antwort grammatisch zu paaren:
    /// ein Adjektiv mit einer Substantiv-Kurzfrage ist eine schlechte Frage.
    public var wordClass: String = ""
    public var sourceRef: String
    public var length: Int { Alphabet.normalize(surface)?.count ?? surface.count }
}

public struct CatalogClue: Sendable {
    public var id: Int32 = 0
    public var answerID: Int32 = 0
    public var text: String
    public var shortText: String?
    public var shortWidth: Int?
    public var kind: ClueKind
    public var tier: Int
    public var locale: String
    public var license: String
    public var sourceRef: String
    /// Kurzform-Kandidaten, absteigend nach Güte — **nicht persistiert**.
    ///
    /// Existiert nur zwischen Ableitung und Ambiguitätsgatter: das Gatter vergibt
    /// Kurzformen und braucht dafür Ausweichmöglichkeiten. Nach dem Gatter steht
    /// die Entscheidung in `shortText`, und dieses Feld wird nicht geschrieben.
    public var shortOptions: [ClueNormalizer.Short] = []
}

public enum CatalogSchema {
    /// Version des **Dateiformats**: kann dieser Leser die Datei überhaupt lesen?
    /// Von Hand erhöhen, wenn sich Tabellen oder Spalten ändern.
    ///
    /// 2: Wortart je Antwort, plus geschärfte Kurzclue-Gatter.
    public static let version = 2

    /// Abdruck des **Inhalts** — die Zahl, die in die `PuzzleID` eingeht.
    ///
    /// Vorher war das dieselbe von Hand gepflegte Zahl wie die Schemaversion, und
    /// das war ein Fehler mit stiller Wirkung: wer den Inhalt ändert und die Zahl
    /// vergisst, verändert jedes Rätsel zum selben Seed. Spielstände zeigen dann
    /// auf ein anderes Gitter, geteilte Links öffnen etwas anderes, und die
    /// geprüfte Seed-Liste erklärt sich weiter für gültig, obwohl sie gegen einen
    /// anderen Katalog geprüft wurde.
    ///
    /// Jetzt entsteht die Zahl aus dem Inhalt selbst und lässt sich nicht
    /// vergessen. Eigenes SHA-256 statt `Hasher`, weil dessen Ergebnis je Prozess
    /// anders ausfällt — dieselbe Regel wie im ganzen Generatorpfad.
    ///
    /// 31 Bit, damit die Zahl in jedem `Int` und in Textform kurz bleibt; die
    /// Reihenfolge ist bedeutungslos, es geht um Identität, nicht um Rangfolge.
    public static func contentFingerprint(answers: [CatalogAnswer],
                                          cluesByAnswer: [String: [CatalogClue]]) -> Int {
        var parts: [String] = ["schema:\(version)"]
        for answer in answers.sorted(by: { $0.surface < $1.surface }) {
            parts.append("a|\(answer.surface)|\(answer.zipf)|\(answer.flags.rawValue)"
                + "|\(answer.wordClass)")
            for clue in (cluesByAnswer[answer.surface] ?? []).sorted(by: { $0.text < $1.text }) {
                parts.append("c|\(clue.text)|\(clue.shortText ?? "")|\(clue.tier)")
            }
        }
        return Int(SHA256.seed(parts.joined(separator: "\n")) & 0x7FFF_FFFF)
    }

    public static let ddl = """
    CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY, value TEXT NOT NULL);

    CREATE TABLE IF NOT EXISTS answers (
        id         INTEGER PRIMARY KEY,
        surface    TEXT    NOT NULL UNIQUE,
        length     INTEGER NOT NULL,
        zipf       REAL    NOT NULL,
        flags      INTEGER NOT NULL,
        word_class TEXT    NOT NULL DEFAULT '',
        source_ref TEXT    NOT NULL);

    CREATE TABLE IF NOT EXISTS clues (
        id          INTEGER PRIMARY KEY,
        answer_id   INTEGER NOT NULL REFERENCES answers(id),
        text        TEXT    NOT NULL,
        short_text  TEXT,
        short_width INTEGER,
        kind        INTEGER NOT NULL,
        tier        INTEGER NOT NULL,
        locale      TEXT    NOT NULL,
        license     TEXT    NOT NULL,
        source_ref  TEXT    NOT NULL);

    CREATE TABLE IF NOT EXISTS topics (
        answer_id INTEGER NOT NULL REFERENCES answers(id),
        topic     TEXT    NOT NULL,
        PRIMARY KEY (answer_id, topic));

    CREATE INDEX IF NOT EXISTS idx_answers_length ON answers(length);
    CREATE INDEX IF NOT EXISTS idx_clues_answer   ON clues(answer_id);
    CREATE INDEX IF NOT EXISTS idx_clues_lookup   ON clues(tier, short_width);
    CREATE INDEX IF NOT EXISTS idx_topics_topic   ON topics(topic);
    """
}

public final class CatalogWriter {
    private let db: SQLiteDatabase

    public init(path: String, fresh: Bool) throws {
        if fresh {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }
        db = try SQLiteDatabase(path: path)
        try db.exec(CatalogSchema.ddl)
    }

    public func setMeta(_ pairs: [String: String]) throws {
        let s = try db.prepare("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)")
        try db.transaction {
            for k in pairs.keys.sorted() { try s.run([.text(k), .text(pairs[k]!)]) }
        }
    }

    /// Schreibt Antworten und Clues in einer Transaktion. Gibt die Anzahl
    /// geschriebener Zeilen zurück.
    public func write(answers: [CatalogAnswer], cluesByAnswer: [String: [CatalogClue]])
        throws -> (answers: Int, clues: Int, topics: Int)
    {
        let insA = try db.prepare("""
            INSERT INTO answers (surface, length, zipf, flags, word_class, source_ref)
            VALUES (?, ?, ?, ?, ?, ?)
            """)
        let insC = try db.prepare("""
            INSERT INTO clues (answer_id, text, short_text, short_width, kind, tier, locale,
                               license, source_ref)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        let insT = try db.prepare("INSERT OR IGNORE INTO topics (answer_id, topic) VALUES (?, ?)")

        var nA = 0, nC = 0, nT = 0
        try db.transaction {
            for a in answers.sorted(by: { $0.surface < $1.surface }) {
                try insA.run([.text(a.surface), .int(a.length), .double(a.zipf),
                              .int(Int(a.flags.rawValue)), .text(a.wordClass),
                              .text(a.sourceRef)])
                let aid = db.lastInsertRowID
                nA += 1
                for t in a.topics.sorted() {
                    try insT.run([.int(aid), .text(t)]); nT += 1
                }
                for c in (cluesByAnswer[a.surface] ?? []) {
                    try insC.run([.int(aid), .text(c.text), .optText(c.shortText),
                                  .optInt(c.shortWidth), .int(c.kind.rawValue),
                                  .int(c.tier), .text(c.locale), .text(c.license),
                                  .text(c.sourceRef)])
                    nC += 1
                }
            }
        }
        return (nA, nC, nT)
    }

    /// Schließt die Datei für die Auslieferung ab.
    ///
    /// Beim Schreiben läuft SQLite im WAL-Modus, das ist schnell. Ausgeliefert
    /// wird aber eine Datei, die **nur gelesen** wird — und eine WAL-Datenbank
    /// braucht selbst zum Lesen Schreibzugriff auf die `-shm`-Datei. Im
    /// App-Bundle gibt es den nicht. Die Nebenwirkung war schon im Test zu sehen:
    /// zwei gleichzeitige Leser bekamen „database is locked".
    ///
    /// Nach dem Umschalten auf `DELETE` verschwinden `-wal` und `-shm`, und die
    /// ausgelieferte Datei ist ein einziges, überall lesbares Artefakt.
    public func finalizeForShipping() throws {
        try db.exec("PRAGMA wal_checkpoint(TRUNCATE);")
        try db.exec("PRAGMA journal_mode = DELETE;")
    }

    public func analyze() throws { try db.exec("ANALYZE;") }
}

/// Liest den Katalog und baut daraus das `Lexicon`, das `PuzzleKit` braucht.
public final class CatalogReader {
    private let db: SQLiteDatabase
    /// Abdruck des Inhalts. Geht in die `PuzzleID` ein.
    public let catalogVersion: Int
    /// Version des Dateiformats.
    public let schemaVersion: Int

    public init(path: String) throws {
        db = try SQLiteDatabase(path: path, readOnly: true, create: false)
        var content = 0
        var schema = 0
        let s = try db.prepare("SELECT key, value FROM meta "
                               + "WHERE key IN ('catalogVersion', 'schemaVersion')")
        try s.query { row in
            switch row.text(0) {
            case "catalogVersion": content = Int(row.text(1)) ?? 0
            case "schemaVersion": schema = Int(row.text(1)) ?? 0
            default: break
            }
        }
        // Ältere Kataloge kannten nur `catalogVersion` und meinten damit das
        // Schema. Fehlt `schemaVersion`, gilt der alte Wert als Schemaversion.
        schemaVersion = schema == 0 ? content : schema
        catalogVersion = content
    }

    /// Baut das Füllvokabular. Ein Wort ohne Clue kommt nicht vor — die
    /// Invariante des ganzen Entwurfs, hier durchgesetzt per JOIN.
    public func loadLexicon(minLength: Int = 3, maxLength: Int = 15) throws -> Lexicon {
        var entries: [LexEntry] = []
        var current: (id: Int32, surface: String, zipf: Double, flags: AnswerFlags)?
        var minShort = [Int32](repeating: Int32.max, count: tierCount)
        var hasClue = [Bool](repeating: false, count: tierCount)

        func flush() {
            guard let c = current, let letters = Alphabet.normalize(c.surface) else { return }
            guard hasClue.contains(true) else { return }
            entries.append(LexEntry(answerID: c.id, letters: letters, zipf: c.zipf,
                                    flags: c.flags, minShortWidthByTier: minShort,
                                    hasClueByTier: hasClue))
        }

        let sql = """
        SELECT a.id, a.surface, a.zipf, a.flags, c.tier, c.short_width
        FROM answers a
        JOIN clues c ON c.answer_id = a.id
        WHERE a.length BETWEEN ? AND ?
        ORDER BY a.id, c.tier
        """
        let s = try db.prepare(sql)
        try s.query([.int(minLength), .int(maxLength)]) { row in
            let id = Int32(row.int(0))
            if current?.id != id {
                flush()
                current = (id, row.text(1), row.double(2),
                           AnswerFlags(rawValue: UInt8(row.int(3))))
                minShort = [Int32](repeating: Int32.max, count: tierCount)
                hasClue = [Bool](repeating: false, count: tierCount)
            }
            let tier = max(1, min(tierCount, row.int(4))) - 1
            hasClue[tier] = true
            if let w = row.optInt(5) {
                minShort[tier] = min(minShort[tier], Int32(w))
            }
        }
        flush()
        return Lexicon(entries: entries, catalogVersion: catalogVersion)
    }

    /// Clues einer Antwort, sortiert nach (tier, id) — deterministisch.
    public func clues(answerID: Int32) throws -> [CatalogClue] {
        var out: [CatalogClue] = []
        let s = try db.prepare("""
            SELECT id, text, short_text, short_width, kind, tier, locale, license, source_ref
            FROM clues WHERE answer_id = ? ORDER BY tier, id
            """)
        try s.query([.int(Int(answerID))]) { r in
            out.append(CatalogClue(id: Int32(r.int(0)), answerID: answerID, text: r.text(1),
                                   shortText: r.optText(2), shortWidth: r.optInt(3),
                                   kind: ClueKind(rawValue: r.int(4)) ?? .definition,
                                   tier: r.int(5), locale: r.text(6), license: r.text(7),
                                   sourceRef: r.text(8)))
        }
        return out
    }

    public func counts() throws -> (answers: Int, clues: Int, withShort: Int) {
        var a = 0, c = 0, w = 0
        try db.prepare("SELECT COUNT(*) FROM answers").query { a = $0.int(0) }
        try db.prepare("SELECT COUNT(*) FROM clues").query { c = $0.int(0) }
        try db.prepare("SELECT COUNT(*) FROM clues WHERE short_text IS NOT NULL")
            .query { w = $0.int(0) }
        return (a, c, w)
    }

    public func meta() throws -> [String: String] {
        var out: [String: String] = [:]
        try db.prepare("SELECT key, value FROM meta").query { out[$0.text(0)] = $0.text(1) }
        return out
    }
}
