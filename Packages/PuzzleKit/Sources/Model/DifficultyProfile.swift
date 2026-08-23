public struct HintPolicy: OptionSet, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let revealLetter = HintPolicy(rawValue: 1 << 0)
    public static let revealWord = HintPolicy(rawValue: 1 << 1)
    public static let checkGrid = HintPolicy(rawValue: 1 << 2)
    public static let finalCheckOnly = HintPolicy(rawValue: 1 << 3)

    public static let all: HintPolicy = [.revealLetter, .revealWord, .checkGrid]
}

/// **Die einzige Stelle für Balancing.** Geschlüsselt nach `(variant, difficulty)`.
///
/// Schwierigkeit ist mehrdimensional: Geometrie, Vokabelseltenheit, Clue-Härte,
/// Hilfen — und bei `arrow` zusätzlich Doppelpfeil- und Knickpfeilanteil, die
/// die Schwierigkeit **ohne** seltenere Wörter erhöhen.
/// **Die einzige Stelle für Balancing.**
///
/// Zwei Abweichungen von der ersten Fassung, beide durch Messung erzwungen:
///
/// **`clueTiers` ist eine Obergrenze, kein Fenster.** „Mittel" heißt „keine
/// Frage härter als Tier 3", nicht „nur Fragen aus Tier 2–3". Weil das Tier aus
/// dem Zipf abgeleitet wird, waren `minZipf` und ein zweiseitiges Tier-Fenster
/// kollinear: für Mittel ergab die Schnittmenge das Band 3,8–4,6 und schloss
/// damit ausgerechnet die häufigsten Wörter aus. Ein mittelschweres Rätsel darf
/// selbstverständlich einfache Fragen enthalten.
///
/// **arrow/leicht: `clueTiers` bis 3.** Dieselbe versteckte Doppelschranke wie
/// unten bei arrow/schwer, nur an anderer Stelle: Tier 1–2 bedeutet bereits
/// zipf >= 4,0 und liegt damit *über* den deklarierten 3,9 — `minZipf` war dort
/// wirkungslos. Gemessen fiel es auf, als geschärfte Kurzclue-Gatter den Pool um
/// 15 % verkleinerten und `minZipf` zu senken **nichts** änderte. Mit Tier bis 3
/// regelt wieder `minZipf` das Vokabular und `clueTiers` die Fragenhärte, ohne
/// sich zu überdecken.
///
/// **arrow/schwer: `clueTiers` bis 5, dafür `minZipf` zurück auf 2,8.** Hier
/// steckte eine versteckte Doppelschranke: Tier 5 beginnt bei zipf < 2,6, und
/// Eigennamen wie Abkürzungen werden zusätzlich um ein Tier hochgesetzt. Mit
/// `clueTiers: 1...4` war das Band also faktisch enger als die 2,4, die
/// darüberstand — und ausgerechnet Eigennamen fielen doppelt heraus. Die
/// Unterscheidung zu Experte trägt jetzt `minZipf` allein (2,8 gegen 2,0), was
/// auch der ehrlichere Regler ist.
///
///
/// **Dieselbe Doppelschranke, drittes und viertes Mal: classic/schwer auf 1...5,
/// arrow/mittel auf 1...4.** Nach der Fragen-Schärfung im Katalog (26 % weniger
/// Kurzformen) scheiterte classic/schwer auf 5 von 6 Seeds und arrow/mittel auf
/// Seed 1. Beide Male band nicht `minZipf`, sondern der Tier-Deckel: Tier 5
/// enthält 129.075 der 164.467 Clues, classic/schwer sah mit `1...4` also ein
/// Fünftel des Katalogs — bei Länge 3, dem knappsten Fach, 370 statt 615
/// Wörtern. Für arrow/mittel bringt Tier 4 bei Länge 3 ganze 31 % zurück
/// (81 → 106 Kurzfragen unter dem Doppelzellen-Budget), Tier 5 danach fast
/// nichts mehr — deshalb 4 und nicht 5: „Mittel" bleibt von der härtesten
/// Fragenstufe verschont.
///
/// Die Regel, die sich damit viermal bestätigt hat: **`minZipf` regelt das
/// Vokabular, `clueTiers` die Fragenhärte, und sie dürfen sich nicht
/// überdecken.** Wer eine Kombination anfasst, prüft zuerst mit SQL, welcher
/// der beiden Werte den Pool wirklich bindet.
/// **arrow/schwer, erste Fassung: zipf >= 2,4.** Der sprechende Vergleich: arrow/experte
/// ist größer (13×17 gegen 13×15) und dichter — und füllt trotzdem, weil sein
/// Band bei 2,0 anfängt. Schwer blieb mit 2,8 konstant bei 15 von 43 Slots
/// stehen, unabhängig vom Knotenbudget. Nicht die Geometrie war zu schwer,
/// sondern der Pool zu klein.
///
/// **arrow/leicht nimmt zipf >= 3,9, nicht 4,5.** Bei 4,5 bleiben katalogweit
/// 1.251 Antworten übrig. Das trägt ein 7×7-Classic-Gitter mit 14 Slots, aber
/// kein 9×11-Schwedenrätsel mit 24 — dort brach die Suche nach 360 Knoten ab.
/// „Leicht" heißt vertraute Wörter, und zipf 3,9 ist noch klar Alltagswortschatz.
///
/// **arrow/leicht beginnt bei Wortlänge 4, nicht 3.** Dreibuchstaber, die
/// gleichzeitig häufig (zipf >= 4,5) sind *und* eine Kurzfrage im halben
/// Zellbudget haben, gibt es im Katalog vierzig. Zwölf solche Slots, die sich
/// gegenseitig kreuzen, sind nicht füllbar — und für ein leichtes Rätsel ist der
/// Verzicht kein Verlust: kurze Dreibuchstaber sind meist Abkürzungen.
///
/// **Arrow-Gitter sind lichter als classic-Gitter derselben Stufe.** Beim
/// Schwedenrätsel muss jede Antwort zusätzlich einen Kurzclue haben, der in seine
/// Zelle passt — bei einer Zelle mit zwei Fragen in die halbe Zelle. Das ist ein
/// weiterer Filter auf demselben Katalog, also muss die Geometrie nachgeben. Mit
/// arrow/mittel bei Kreuzungsanteil 0,50–0,72 (dichter als classic/schwer) kam
/// die Füllung über 22 von 36 Slots nicht hinaus.
///
/// **Knickpfeile gibt es auch bei „Leicht" — 8 %, nicht 0 %.** Mit einer Quote
/// von exakt null darf kein waagrechter Lauf am linken Rand beginnen und kein
/// senkrechter oben, weil dort keine Zelle liegt, aus der ein gerader Pfeil
/// zeigen könnte. In einem 9×11 mit 24 Fragezellen ist das nicht erfüllbar, und
/// gedruckte leichte Schwedenrätsel enthalten sehr wohl einzelne Knickpfeile.
///
/// **Der Kreuzungsanteil steigt mit der Schwierigkeit, nicht umgekehrt.** Für
/// den Spieler bedeuten mehr Kreuzungen mehr Hinweise, also *leichter*; für den
/// Generator bedeuten sie mehr Constraints, also *schwerer*. Da das
/// Vokabularband der Stufe „Leicht" mit 1.251 Antworten das kleinste ist, kann
/// gerade dort das Gitter nicht das dichteste sein. Die Auflösung: Schwierigkeit
/// wächst über *beide* Achsen gemeinsam — seltenere Wörter **und** dichtere
/// Verzahnung. Leichte Rätsel sind licht und vertraut, schwere dicht und selten.
///
/// **`crossRatio` < 1, also keine volle Verzahnung.** Voll verzahnte Gitter
/// (jeder Buchstabe in zwei Wörtern) sind die amerikanische Bauform und
/// verlangen Wortlisten in der Größenordnung 50.000 pro Schwierigkeitsband. Der
/// Katalog hat bei zipf >= 4,5 aber 1.251 Antworten. Deutschsprachige
/// Kreuzworträtsel sind traditionell ohnehin nicht voll verzahnt: einzelne
/// Buchstaben stehen nur in einem Wort. Die Regel lautet jetzt für **beide**
/// Varianten: Läufe der Länge 1 sind erlaubt, Läufe der Länge 2 nicht.
///
/// Zur Wortlänge: die Obergrenzen liegen bewusst deutlich **unter** der
/// Gitterkante. Ein Muster, in dem eine Zeile über die volle Breite ein Wort
/// ist, erzeugt gestapelte Langwörter — und die sind mit einem prozeduralen
/// Füller praktisch nicht lösbar. Der erste Lauf scheiterte genau daran: ein
/// 11×11 mit sechs 11-Buchstaben-Slots blieb bei 0 von 38 belegten Slots.
public struct DifficultyProfile: Sendable {
    public let variant: PuzzleVariant
    public let difficulty: Difficulty

    public let sizes: [GridSize]
    /// `classic`: Schwarzfeldanteil. `arrow`: Fragezellenanteil.
    public let deadCellRatio: ClosedRange<Double>
    public let maxDoubleArrowRatio: Double
    public let maxBentArrowRatio: Double
    public let wordLength: ClosedRange<Int>
    public let minZipf: Double
    public let clueTiers: ClosedRange<Int>
    public let maxProperNounRatio: Double
    /// **Zielband** für den Anteil der Buchstaben, die in zwei Wörtern liegen.
    ///
    /// Kein Mindestwert, sondern ein Band: 1,0 (volle Verzahnung) ist nicht nur
    /// schwer füllbar, sondern mit diesem Katalog unmöglich. Die Templatesuche
    /// steuert bewusst **in** dieses Band hinein.
    public let crossRatio: ClosedRange<Double>
    /// Breitenbudget in 1/1000 em für eine Fragezelle mit einem bzw. zwei Clues.
    public let singleClueBudget: Int
    public let doubleClueBudget: Int
    public let parSeconds: Double
    public let referenceLetterCells: Int
    public let hints: HintPolicy
    public let nodeBudget: Int
    public let maxAttempts: Int

    public static func profile(_ variant: PuzzleVariant, _ difficulty: Difficulty) -> DifficultyProfile {
        switch (variant, difficulty) {
        // MARK: classic
        case (.classic, .leicht):
            .init(variant: variant, difficulty: difficulty,
                  sizes: [GridSize(square: 7), GridSize(square: 9)],
                  deadCellRatio: 0.20 ... 0.26, maxDoubleArrowRatio: 0, maxBentArrowRatio: 0,
                  wordLength: 3 ... 7, minZipf: 4.5, clueTiers: 1 ... 2,
                  maxProperNounRatio: 0.05, crossRatio: 0.40 ... 0.56,
                  singleClueBudget: 0, doubleClueBudget: 0,
                  parSeconds: 360, referenceLetterCells: 55, hints: .all,
                  nodeBudget: 250_000, maxAttempts: 8)
        case (.classic, .mittel):
            .init(variant: variant, difficulty: difficulty,
                  sizes: [GridSize(square: 11)],
                  deadCellRatio: 0.17 ... 0.22, maxDoubleArrowRatio: 0, maxBentArrowRatio: 0,
                  wordLength: 3 ... 8, minZipf: 3.4, clueTiers: 1 ... 3,
                  maxProperNounRatio: 0.10, crossRatio: 0.44 ... 0.60,
                  singleClueBudget: 0, doubleClueBudget: 0,
                  parSeconds: 840, referenceLetterCells: 99, hints: .all,
                  nodeBudget: 400_000, maxAttempts: 8)
        case (.classic, .schwer):
            .init(variant: variant, difficulty: difficulty,
                  sizes: [GridSize(square: 13)],
                  deadCellRatio: 0.15 ... 0.20, maxDoubleArrowRatio: 0, maxBentArrowRatio: 0,
                  wordLength: 3 ... 9, minZipf: 2.8, clueTiers: 1 ... 5,
                  maxProperNounRatio: 0.15, crossRatio: 0.50 ... 0.66,
                  singleClueBudget: 0, doubleClueBudget: 0,
                  parSeconds: 1500, referenceLetterCells: 141,
                  hints: [.revealLetter, .checkGrid],
                  nodeBudget: 600_000, maxAttempts: 8)
        case (.classic, .experte):
            .init(variant: variant, difficulty: difficulty,
                  sizes: [GridSize(square: 15)],
                  deadCellRatio: 0.13 ... 0.18, maxDoubleArrowRatio: 0, maxBentArrowRatio: 0,
                  wordLength: 3 ... 10, minZipf: 2.0, clueTiers: 1 ... 5,
                  maxProperNounRatio: 0.20, crossRatio: 0.54 ... 0.70,
                  singleClueBudget: 0, doubleClueBudget: 0,
                  parSeconds: 2700, referenceLetterCells: 192, hints: [.finalCheckOnly],
                  nodeBudget: 2_500_000, maxAttempts: 10)

        // MARK: arrow (Schwedenrätsel)
        case (.arrow, .leicht):
            .init(variant: variant, difficulty: difficulty,
                  sizes: [GridSize(rows: 11, cols: 9)],
                  deadCellRatio: 0.24 ... 0.36, maxDoubleArrowRatio: 0.18, maxBentArrowRatio: 0.10,
                  wordLength: 4 ... 7, minZipf: 3.9, clueTiers: 1 ... 3,
                  maxProperNounRatio: 0.05, crossRatio: 0.34 ... 0.50,
                  singleClueBudget: 16_000, doubleClueBudget: 9_500,
                  parSeconds: 420, referenceLetterCells: 75, hints: .all,
                  nodeBudget: 300_000, maxAttempts: 10)
        case (.arrow, .mittel):
            .init(variant: variant, difficulty: difficulty,
                  sizes: [GridSize(rows: 13, cols: 11)],
                  deadCellRatio: 0.22 ... 0.32, maxDoubleArrowRatio: 0.28, maxBentArrowRatio: 0.16,
                  wordLength: 3 ... 9, minZipf: 3.4, clueTiers: 1 ... 4,
                  maxProperNounRatio: 0.10, crossRatio: 0.40 ... 0.54,
                  singleClueBudget: 16_000, doubleClueBudget: 9_500,
                  parSeconds: 900, referenceLetterCells: 111, hints: .all,
                  nodeBudget: 500_000, maxAttempts: 10)
        case (.arrow, .schwer):
            .init(variant: variant, difficulty: difficulty,
                  sizes: [GridSize(rows: 15, cols: 13)],
                  deadCellRatio: 0.18 ... 0.26, maxDoubleArrowRatio: 0.55, maxBentArrowRatio: 0.22,
                  wordLength: 3 ... 8, minZipf: 2.8, clueTiers: 1 ... 5,
                  maxProperNounRatio: 0.15, crossRatio: 0.42 ... 0.56,
                  singleClueBudget: 16_000, doubleClueBudget: 9_500,
                  parSeconds: 1560, referenceLetterCells: 155,
                  hints: [.revealLetter, .checkGrid],
                  nodeBudget: 1_500_000, maxAttempts: 10)
        case (.arrow, .experte):
            .init(variant: variant, difficulty: difficulty,
                  sizes: [GridSize(rows: 17, cols: 13)],
                  deadCellRatio: 0.17 ... 0.25, maxDoubleArrowRatio: 0.65, maxBentArrowRatio: 0.32,
                  wordLength: 3 ... 11, minZipf: 2.0, clueTiers: 1 ... 5,
                  maxProperNounRatio: 0.20, crossRatio: 0.50 ... 0.64,
                  singleClueBudget: 16_000, doubleClueBudget: 9_500,
                  parSeconds: 2700, referenceLetterCells: 178, hints: [.finalCheckOnly],
                  nodeBudget: 1_000_000, maxAttempts: 10)
        }
    }

    public static var all: [DifficultyProfile] {
        PuzzleVariant.allCases.flatMap { v in Difficulty.allCases.map { profile(v, $0) } }
    }
}
