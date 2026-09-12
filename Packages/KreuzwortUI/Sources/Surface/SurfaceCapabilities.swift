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
    /// **Die Bedingung hieß einmal `!hasHardwareKeyboard && hasFocusEngine`**
    /// — die Leiste war als Lösung für den Fernseher gedacht. Das war zu eng
    /// gefasst: ein iPhone hat genauso wenig Tastatur wie eine Fernbedienung.
    /// Gemessen auf dem iPhone-Simulator zählte der Rätselbildschirm sieben
    /// Knöpfe — zwei für den Fragewechsel, fünf Hilfen — und keinen einzigen
    /// Buchstaben. Eine Bildschirmtastatur gibt es nirgends im Projekt (kein
    /// `TextField`, kein `UIKeyInput`), und `onKeyPress` antwortet nur auf
    /// echte Tasten. Ohne angeschlossene Tastatur ließ sich dort kein
    /// Buchstabe eintragen; die einzigen Wege ins Gitter waren „Buchstabe
    /// aufdecken" und „Wort aufdecken".
    ///
    /// Die Frage ist also allein, ob es eine Tastatur gibt — nicht, wie der
    /// Fokus wandert.
    public var needsOnScreenLetters: Bool { !hasHardwareKeyboard }

    /// Steht die Buchstabenleiste **neben** dem Gitter statt darunter?
    ///
    /// Nur dort, wo die Höhe knapp und die Breite im Überfluss vorhanden ist:
    /// auf dem Fernseher. Unter dem Gitter kostete die Leiste dort rund 270 pt
    /// und drückte die Zellen auf etwa 30 pt. Auf einem Telefon ist es genau
    /// umgekehrt — dort gehört sie nach unten, wie man es von Tastaturen
    /// gewohnt ist.
    public var lettersBesideGrid: Bool { viewingDistance == .far }

    /// Soll die Tastaturbehandlung angebaut werden?
    ///
    /// **Nicht an `hasHardwareKeyboard` gebunden.** Ob gerade eine Tastatur am
    /// iPad steckt, weiß diese Beschreibung nicht — sie meldet dort immer
    /// `false`. Ein erster Anlauf knüpfte den Modifier daran und nahm damit
    /// dem iPad mit Magic Keyboard die Eingabe weg.
    ///
    /// Entscheidend ist, wo der Modifier **schadet**: er macht den ganzen
    /// Bildschirm fokussierbar und nimmt auf dem Fernseher den Teilbaum aus
    /// dem Fokussystem — dort war die App dadurch unbedienbar. Wo es keine
    /// Fokus-Engine gibt, ist er harmlos und bringt jede angeschlossene
    /// Tastatur zum Laufen.
    public var handlesHardwareKeys: Bool { !hasFocusEngine }

    /// Mindestkantenlänge einer Zelle in Punkten.
    public var minimumCellSide: Double {
        switch viewingDistance {
        case .near: 34      // Trefferfläche für den Finger
        case .medium: 28
        case .far: 48       // Lesbarkeit aus drei Metern
        }
    }
}
