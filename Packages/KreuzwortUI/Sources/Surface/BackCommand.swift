import SwiftUI
import PuzzleKit

/// Wie eine Fläche „zurück" meldet.
///
/// **Warum das hereingereicht wird.** Auf dem Fernseher ist „zurück" die
/// Back-Taste der Fernbedienung, und die fängt man mit `onExitCommand`. Diesen
/// Modifier gibt es auf iOS nicht — er ließe sich hier also nur hinter einem
/// `#if os(tvOS)` anbringen. Genau das verbietet der Seam-Test für dieses
/// Paket, und zwar zu Recht: Plattformverhalten gehört in die App-Targets, die
/// Fähigkeiten hierher.
///
/// Also liefert das App-Target den Modifier, und diese Ebene weiß nur, **wo**
/// „zurück" gelten soll — nämlich in der Buchstabenauswahl.
public typealias BackCommand =
    @MainActor (AnyView, @escaping () -> Void) -> AnyView

/// Ohne Rückwärtsgang: die Ansicht bleibt, wie sie ist.
@MainActor public let noBackCommand: BackCommand = { view, _ in view }

/// Worauf der Fokus im Rätsel steht.
///
/// **Ein gemeinsamer Zustand für Gitter und Buchstaben.** Vorher hatte jede
/// Ansicht ihren eigenen `FocusState`; damit konnte keine die andere
/// anspringen, und die Fernbedienung musste die Strecke dazwischen jedes Mal
/// zu Fuß gehen.
public enum PuzzleFocus: Hashable, Sendable {
    case cell(Cell)
    case letter(Character)
    case delete
}
