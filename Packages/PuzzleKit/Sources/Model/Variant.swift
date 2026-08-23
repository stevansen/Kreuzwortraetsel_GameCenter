public enum PuzzleVariant: String, Codable, Sendable, CaseIterable {
    /// Numeriertes Gitter mit Schwarzfeldern, Fragen in einer Liste daneben.
    case classic
    /// Schwedenrätsel: Fragen stehen in Zellen im Gitter, Pfeile zeigen die Laufrichtung.
    case arrow

    public var label: String {
        self == .classic ? "Klassisch" : "Schwedenrätsel"
    }
}

public enum Difficulty: String, Codable, Sendable, CaseIterable {
    case leicht, mittel, schwer, experte

    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    public var basePoints: Int {
        switch self {
        case .leicht: 100
        case .mittel: 250
        case .schwer: 500
        case .experte: 900
        }
    }
}

/// Pfeilarten einer Fragezelle.
///
/// Die Zelle liegt bei `(r, c)`; angegeben ist, wo die Antwort **beginnt** und
/// in welche Richtung sie **läuft**. Bei den Knickpfeilen fallen beide auseinander
/// — das ist die zusätzliche Denkstufe, die sie schwerer macht.
public enum ArrowKind: String, Codable, Sendable, CaseIterable {
    /// Start `(r, c+1)`, läuft waagrecht.
    case right
    /// Start `(r+1, c)`, läuft senkrecht.
    case down
    /// Knick: Start `(r, c+1)`, läuft senkrecht.
    case rightThenDown
    /// Knick: Start `(r+1, c)`, läuft waagrecht.
    case downThenRight
    /// Knick: Start `(r, c-1)`, läuft senkrecht.
    case leftThenDown
    /// Knick: Start `(r-1, c)`, läuft waagrecht.
    case upThenRight

    public var isBent: Bool {
        switch self {
        case .right, .down: false
        default: true
        }
    }

    /// Startzelle der Antwort, relativ zur Fragezelle.
    public var startOffset: (dr: Int, dc: Int) {
        switch self {
        case .right, .rightThenDown: (0, 1)
        case .down, .downThenRight: (1, 0)
        case .leftThenDown: (0, -1)
        case .upThenRight: (-1, 0)
        }
    }

    public var runDirection: Direction {
        switch self {
        case .right, .downThenRight, .upThenRight: .across
        case .down, .rightThenDown, .leftThenDown: .down
        }
    }

    /// Glyphe für die ASCII-Vorschau der CLI.
    public var glyph: String {
        switch self {
        case .right: "→"
        case .down: "↓"
        case .rightThenDown: "⇲"
        case .downThenRight: "⇱"
        case .leftThenDown: "⇱"
        case .upThenRight: "⇲"
        }
    }

    public static func kind(startOffset: (dr: Int, dc: Int), run: Direction) -> ArrowKind? {
        allCases.first { $0.startOffset == startOffset && $0.runDirection == run }
    }
}
