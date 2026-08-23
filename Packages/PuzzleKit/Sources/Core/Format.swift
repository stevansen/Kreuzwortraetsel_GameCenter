/// Kleine Zahlformatierung ohne Foundation.
///
/// `PuzzleKit` importiert absichtlich kein Foundation: das Paket muss für jede
/// Zielplattform bauen, in der CLI laufen und plattformneutral bleiben.
/// `String(format:)` wäre die einzige Stelle gewesen, die das gebrochen hätte.
public func fmt(_ value: Double, _ places: Int = 3) -> String {
    if value.isNaN { return "NaN" }
    var scale = 1.0
    for _ in 0 ..< places { scale *= 10 }
    let neg = value < 0
    let rounded = (value.magnitude * scale).rounded()
    let whole = Int(rounded / scale)
    let frac = Int(rounded) - whole * Int(scale)
    var fracStr = String(frac)
    while fracStr.count < places { fracStr = "0" + fracStr }
    return (neg ? "-" : "") + String(whole) + (places > 0 ? "." + fracStr : "")
}

public func pct(_ value: Double) -> String { fmt(value * 100, 1) + " %" }
