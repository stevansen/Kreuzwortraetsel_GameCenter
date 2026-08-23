/// Ein Buchstabe im Gitter, als Index in `Alphabet.characters` (0 ..< 29).
public typealias Letter = UInt8

/// Das Gitteralphabet: A–Z plus die drei Umlaute als **eigene Zellen**.
///
/// `ß` wird beim Normalisieren zu `SS`. Bindestriche, Leerzeichen und alles
/// andere führen zur Ablehnung — was hier nicht durchkommt, kommt nie ins Gitter.
public enum Alphabet {
    public static let characters: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ")
    public static let count = 29

    private static let indexByCharacter: [Character: Letter] = {
        var m: [Character: Letter] = [:]
        for (i, c) in characters.enumerated() { m[c] = Letter(i) }
        return m
    }()

    public static func index(of c: Character) -> Letter? { indexByCharacter[c] }

    public static func character(_ l: Letter) -> Character {
        characters[Int(l)]
    }

    /// Normalisiert eine Oberflächenform zu Gitterbuchstaben.
    /// Gibt `nil` zurück, wenn irgendein Zeichen nicht darstellbar ist.
    public static func normalize(_ s: String) -> [Letter]? {
        var out: [Letter] = []
        out.reserveCapacity(s.count + 2)
        for ch in s.uppercased() {
            if ch == "ß" || ch == "ẞ" {
                out.append(index(of: "S")!); out.append(index(of: "S")!)
                continue
            }
            guard let i = index(of: ch) else { return nil }
            out.append(i)
        }
        return out
    }

    public static func string(_ letters: [Letter]) -> String {
        String(letters.map(character))
    }
}
