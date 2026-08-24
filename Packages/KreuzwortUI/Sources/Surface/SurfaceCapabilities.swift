import PuzzleKit

/// Was die Fläche kann, auf der gespielt wird.
///
/// **Fähigkeiten, nicht Betriebssysteme.** `#if os(tvOS)` ist die naheliegende
/// und falsche Antwort auf vier Plattformen, weil die Unterschiede nicht sauber
/// entlang der Systeme liegen: ein iPad hat manchmal eine Tastatur und manchmal
/// nicht, ein Mac im Vollbild verhält sich wie ein Tablet, ein iPhone im
/// Querformat hat andere Platzverhältnisse als im Hochformat.
///
/// Die Erkennung selbst liegt bewusst **nicht** hier, sondern in den
/// App-Targets: dieses Paket soll frei von Plattformverzweigung bleiben (ein
/// Test scannt darauf), und ein injizierbarer Wert lässt sich in Previews und
/// Tests beliebig setzen.
public struct SurfaceCapabilities: Sendable, Hashable {
    /// Können Kurzfragen **in** den Zellen stehen? Auf einem Fernseher aus drei
    /// Metern Entfernung nicht — dort tragen Clue-Leiste und Clue-Liste alles.
    public var rendersInCellClues: Bool
    public var hasHardwareKeyboard: Bool
    public var hasPointer: Bool
    public var hasFocusEngine: Bool
    public var supportsZoomPan: Bool
    /// Betrachtungsabstand — steuert Mindestschriftgrößen und Trefferflächen.
    public var viewingDistance: ViewingDistance

    public enum ViewingDistance: Sendable, Hashable {
        /// Hand: Telefon, Tablet.
        case near
        /// Schreibtisch: Mac.
        case medium
        /// Wohnzimmer: Fernseher.
        case far
    }

    public init(rendersInCellClues: Bool, hasHardwareKeyboard: Bool, hasPointer: Bool,
                hasFocusEngine: Bool, supportsZoomPan: Bool,
                viewingDistance: ViewingDistance) {
        self.rendersInCellClues = rendersInCellClues
        self.hasHardwareKeyboard = hasHardwareKeyboard
        self.hasPointer = hasPointer
        self.hasFocusEngine = hasFocusEngine
        self.supportsZoomPan = supportsZoomPan
        self.viewingDistance = viewingDistance
    }

    /// Handheld mit Touch, ohne angeschlossene Tastatur.
    public static let touch = SurfaceCapabilities(
        rendersInCellClues: true, hasHardwareKeyboard: false, hasPointer: false,
        hasFocusEngine: false, supportsZoomPan: true, viewingDistance: .near)

    /// Schreibtisch: Tastatur zuerst, Zeiger vorhanden, kein Zoom nötig.
    public static let desktop = SurfaceCapabilities(
        rendersInCellClues: true, hasHardwareKeyboard: true, hasPointer: true,
        hasFocusEngine: false, supportsZoomPan: false, viewingDistance: .medium)

    /// Großes Tablet: Platz für die Seitenspalte wie am Schreibtisch, aber Touch
    /// — also größere Trefferflächen und Zoom.
    public static let desktopTouch = SurfaceCapabilities(
        rendersInCellClues: true, hasHardwareKeyboard: false, hasPointer: true,
        hasFocusEngine: false, supportsZoomPan: true, viewingDistance: .near)

    /// Wohnzimmer: Fokus-Fernbedienung, kein Zeiger, keine Fragen in Zellen.
    public static let livingRoom = SurfaceCapabilities(
        rendersInCellClues: false, hasHardwareKeyboard: false, hasPointer: false,
        hasFocusEngine: true, supportsZoomPan: false, viewingDistance: .far)

    // MARK: - Abgeleitete Darstellungsentscheidungen

    /// Ist die aktive-Clue-Leiste die **primäre** Anzeige der Frage?
    ///
    /// Sie ist immer vorhanden — auf Flächen ohne Fragen in Zellen ist sie
    /// zusätzlich der einzige Weg, die Frage zu lesen.
    public var clueBarIsPrimary: Bool { !rendersInCellClues }

    /// Steht die Fragenliste dauerhaft neben dem Gitter?
    ///
    /// Nicht an `hasPointer` gebunden, wie es zuerst war: der Fernseher hat
    /// keinen Zeiger, aber die breiteste Fläche von allen — und weil dort keine
    /// Fragen in den Zellen stehen, ist die Liste dort **wichtiger** als
    /// irgendwo sonst. Sie hinter einem Blatt zu verstecken hieße, das Rätsel
    /// unspielbar zu machen.
    public var showsSideClueList: Bool { hasPointer || hasFocusEngine }

    /// Braucht die Fläche Buchstaben auf dem Schirm?
    ///
    /// Die Fernbedienung liefert Fokusbewegung und „Auswählen", aber keine
    /// Zeichen. Ohne Tastatur und mit Fokus-Engine ist eine Buchstabenleiste der
    /// einzige Weg, überhaupt etwas einzutragen.
    public var needsOnScreenLetters: Bool { !hasHardwareKeyboard && hasFocusEngine }

    /// Mindestkantenlänge einer Zelle in Punkten.
    public var minimumCellSide: Double {
        switch viewingDistance {
        case .near: 34      // Trefferfläche für den Finger
        case .medium: 28
        case .far: 48       // Lesbarkeit aus drei Metern
        }
    }
}
