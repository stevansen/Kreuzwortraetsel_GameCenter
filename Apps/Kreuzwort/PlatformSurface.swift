import SwiftUI
import KreuzwortUI

// **Der einzige Ort im Projekt, an dem nach der Plattform gefragt wird.**
//
// `KreuzwortUI` bleibt frei von `#if os(...)` — ein Test scannt das Verzeichnis
// darauf. Hier wird die Fähigkeitsbeschreibung erzeugt und hineingegeben.
//
// Die Verzweigung ist absichtlich flach: sie bildet nur ab, was die Plattform
// *kann*. Alles Weitere entscheidet die Oberfläche anhand dieser Fähigkeiten,
// und zwar auch innerhalb einer Plattform — ein iPad mit Tastatur verhält sich
// anders als eines ohne.

enum PlatformSurface {
    /// Fähigkeiten für die aktuelle Fläche.
    ///
    /// - Parameter horizontalSizeClass: iPadOS im Splitscreen ist schmal wie ein
    ///   iPhone; die Größenklasse ist dort die verlässlichere Auskunft als das
    ///   Betriebssystem.
    static func capabilities(compact: Bool) -> SurfaceCapabilities {
        #if os(tvOS)
        return .livingRoom
        #elseif os(macOS)
        return .desktop
        #else
        // iOS und iPadOS: breit und mit Zeiger wie ein Schreibtisch, schmal wie
        // ein Handheld. Ein iPad im Vollbild bekommt die Seitenspalte, im
        // Splitscreen die Leiste.
        return compact ? .touch : .desktopTouch
        #endif
    }
}
