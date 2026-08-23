/// Bitset-Index über das Füllvokabular.
///
/// Für jede Wortlänge `L`: pro Position und Buchstabe ein Bitset über die
/// Antworten dieser Länge. Die Kandidaten eines teilbefüllten Slots sind der
/// **Schnitt** der Bitsets aller bekannten Buchstaben. Das ist der Grund, dass
/// die MRV-Heuristik bezahlbar ist: sie braucht in jedem Suchknoten die
/// Kandidatenzahl **jedes** offenen Slots, und die kostet hier ein paar
/// Wortoperationen statt eines Stringvergleichs.
public struct PatternIndex: Sendable {
    public struct LengthIndex: Sendable {
        public let length: Int
        /// Lokaler Index -> globaler Lexicon-Index.
        public let gids: [Int]
        public let letters: [[Letter]]
        public let zipf: [Double]
        public let flags: [AnswerFlags]
        /// [lokaler Index][tier 0..<5] -> kleinste Kurzclue-Breite, `Int32.max` = keiner.
        public let minShortWidthByTier: [[Int32]]
        public let hasClueByTier: [[Bool]]
        /// `bits[pos * Alphabet.count + letter]`
        let bits: [Bitset]
        let properNounMask: Bitset

        public var count: Int { gids.count }

        @inline(__always)
        func bitset(pos: Int, letter: Letter) -> Bitset {
            bits[pos * Alphabet.count + Int(letter)]
        }
    }

    public let lengths: [Int: LengthIndex]
    public let lexicon: Lexicon

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
        var out: [Int: LengthIndex] = [:]
        for (length, gids) in lexicon.byLength {
            let n = gids.count
            var letters: [[Letter]] = []
            var zipf: [Double] = []
            var flags: [AnswerFlags] = []
            var shortW: [[Int32]] = []
            var hasClue: [[Bool]] = []
            letters.reserveCapacity(n); zipf.reserveCapacity(n)
            var bits = [Bitset](repeating: Bitset(bitCount: n), count: length * Alphabet.count)
            var pn = Bitset(bitCount: n)
            for (local, gid) in gids.enumerated() {
                let e = lexicon.entries[gid]
                letters.append(e.letters)
                zipf.append(e.zipf)
                flags.append(e.flags)
                shortW.append(e.minShortWidthByTier)
                hasClue.append(e.hasClueByTier)
                for (pos, l) in e.letters.enumerated() {
                    bits[pos * Alphabet.count + Int(l)].set(local)
                }
                if e.flags.contains(.properNoun) { pn.set(local) }
            }
            out[length] = LengthIndex(length: length, gids: gids, letters: letters,
                                      zipf: zipf, flags: flags,
                                      minShortWidthByTier: shortW, hasClueByTier: hasClue,
                                      bits: bits, properNounMask: pn)
        }
        self.lengths = out
    }

    // MARK: - Filtermasken

    /// Was eine Antwort erfüllen muss, um für ein Slot in Frage zu kommen.
    ///
    /// `maxShortWidth` ist bei `classic` `nil` (Kurzclue irrelevant) und bei
    /// `arrow` das Budget der Fragezelle, die dieses Slot besitzt.
    public struct WordFilter: Hashable, Sendable {
        public let minZipf: Double
        public let tiers: ClosedRange<Int>
        public let maxShortWidth: Int?

        public init(minZipf: Double, tiers: ClosedRange<Int>, maxShortWidth: Int?) {
            self.minZipf = minZipf
            self.tiers = tiers
            self.maxShortWidth = maxShortWidth
        }
    }

    /// Vorberechnete Maske: alle Antworten dieser Länge, die den Filter erfüllen.
    public func mask(length: Int, filter: WordFilter) -> Bitset {
        guard let idx = lengths[length] else { return Bitset(bitCount: 0) }
        var m = Bitset(bitCount: idx.count)
        for local in 0 ..< idx.count {
            guard idx.zipf[local] >= filter.minZipf else { continue }
            var ok = false
            for tier in filter.tiers {
                let t = tier - 1
                guard t >= 0, t < tierCount else { continue }
                if let budget = filter.maxShortWidth {
                    if idx.minShortWidthByTier[local][t] <= Int32(budget) { ok = true; break }
                } else if idx.hasClueByTier[local][t] {
                    ok = true; break
                }
            }
            if ok { m.set(local) }
        }
        return m
    }

    public func properNounMask(length: Int) -> Bitset {
        lengths[length]?.properNounMask ?? Bitset(bitCount: 0)
    }
}
