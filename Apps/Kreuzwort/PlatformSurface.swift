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

/// Wie „zurück" auf dieser Plattform gemeldet wird.
///
/// **Nur der Fernseher hat eine Back-Taste.** Dort fängt `onExitCommand` sie
/// ab — den Modifier gibt es auf iOS nicht, deshalb steht die Verzweigung hier
/// und nicht in `KreuzwortUI`: das Paket soll frei von Plattformverhalten
/// bleiben, und ein Seam-Test prüft das.
///
/// Angebracht wird er nur an der Buchstabenauswahl. Läge er über dem ganzen
/// Rätsel, schluckte er die Taste auch im Gitter — und damit den Weg aus der
/// App heraus.
extension PlatformSurface {
    @MainActor static var backCommand: BackCommand {
        #if os(tvOS)
        return { view, action in AnyView(view.onExitCommand(perform: action)) }
        #else
        return noBackCommand
        #endif
    }
}
