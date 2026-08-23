public struct ClueChoice: Sendable, Hashable {
    public let id: Int32
    public let text: String
    public let shortText: String?
    public let shortWidth: Int?
    public let kind: Int
    public let tier: Int

    public init(id: Int32, text: String, shortText: String?, shortWidth: Int?,
                kind: Int, tier: Int) {
        self.id = id
        self.text = text
        self.shortText = shortText
        self.shortWidth = shortWidth
        self.kind = kind
        self.tier = tier
    }
}

/// Woher die Fragetexte kommen. `PuzzleKit` kennt keine Datenbank — die
/// Implementierung liegt in `ClueCatalog`, für Tests gibt es eine In-Memory-Variante.
public protocol ClueSource: Sendable {
    /// Wählt eine Frage für die Antwort.
    ///
    /// - `maxShortWidth`: bei `arrow` das Breitenbudget der besitzenden
    ///   Fragezelle, bei `classic` `nil`.
    /// - `usedTexts`: bereits im Rätsel vergebene Fragetexte. Wird nur mit
    ///   `contains` befragt und **nie** iteriert — Set-Iteration wäre nicht
    ///   deterministisch.
    func clue(answerID: Int32, tiers: ClosedRange<Int>, maxShortWidth: Int?,
              usedTexts: Set<String>, usedKinds: [Int: Int], slotCount: Int,
              rng: inout SplitMix64) -> ClueChoice?
}
