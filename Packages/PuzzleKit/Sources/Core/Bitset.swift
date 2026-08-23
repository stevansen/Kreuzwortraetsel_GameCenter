/// Feste Bitmenge über `[UInt64]`. Der Pattern-Index besteht daraus, und
/// Kandidatenmengen werden nur über Schnitt/Differenz gebildet — nie über Strings.
public struct Bitset: Equatable, Sendable {
    @usableFromInline var words: [UInt64]
    @usableFromInline let bitCount: Int

    public init(bitCount: Int, filled: Bool = false) {
        self.bitCount = bitCount
        let wordCount = (bitCount + 63) / 64
        self.words = [UInt64](repeating: filled ? .max : 0, count: wordCount)
        if filled { maskTail() }
    }

    @inlinable public var capacity: Int { bitCount }

    private mutating func maskTail() {
        let rem = bitCount % 64
        if rem != 0, !words.isEmpty {
            words[words.count - 1] &= (UInt64(1) << UInt64(rem)) - 1
        }
    }

    @inlinable public mutating func set(_ i: Int) { words[i >> 6] |= UInt64(1) << UInt64(i & 63) }
    @inlinable public mutating func clear(_ i: Int) { words[i >> 6] &= ~(UInt64(1) << UInt64(i & 63)) }
    @inlinable public func test(_ i: Int) -> Bool { words[i >> 6] & (UInt64(1) << UInt64(i & 63)) != 0 }

    @inlinable
    public mutating func formIntersection(_ other: Bitset) {
        for i in 0 ..< words.count { words[i] &= other.words[i] }
    }

    @inlinable
    public mutating func subtract(_ other: Bitset) {
        for i in 0 ..< words.count { words[i] &= ~other.words[i] }
    }

    @inlinable
    public var isEmpty: Bool {
        for w in words where w != 0 { return false }
        return true
    }

    @inlinable
    public var count: Int {
        var n = 0
        for w in words { n += w.nonzeroBitCount }
        return n
    }

    /// Zählt den Schnitt, ohne ihn zu materialisieren — der heiße Pfad der MRV-Heuristik.
    @inlinable
    public func intersectionCount(_ other: Bitset) -> Int {
        var n = 0
        for i in 0 ..< words.count { n += (words[i] & other.words[i]).nonzeroBitCount }
        return n
    }

    @inlinable
    public func intersectionIsEmpty(_ other: Bitset) -> Bool {
        for i in 0 ..< words.count where words[i] & other.words[i] != 0 { return false }
        return true
    }

    /// Gesetzte Bits in aufsteigender Reihenfolge — deterministisch.
    public func forEachSetBit(_ body: (Int) -> Void) {
        for wi in 0 ..< words.count {
            var w = words[wi]
            while w != 0 {
                let t = w.trailingZeroBitCount
                body(wi * 64 + t)
                w &= w - 1
            }
        }
    }

    public var indices: [Int] {
        var out: [Int] = []
        out.reserveCapacity(count)
        forEachSetBit { out.append($0) }
        return out
    }
}
