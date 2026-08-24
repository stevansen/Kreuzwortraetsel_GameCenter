import SwiftUI
import PuzzleKit

/// Buchstaben auf dem Schirm, für Flächen ohne Tastatur.
///
/// **Warum überhaupt.** Die Apple-TV-Fernbedienung liefert Fokusbewegung und
/// „Auswählen" — keine Zeichen. Die gesamte Eingabe der App hing an
/// `onKeyPress`; auf dem Fernseher liess sich damit kein einziger Buchstabe
/// eintragen. Diese Leiste ist dort der einzige Eingabeweg.
///
/// **Warum kein `ScrollView`.** 29 Knöpfe in einer scrollenden Zeile wären auf
/// dem Fernseher unbequem (jeder Buchstabe hinter einer Fokusreise) und würden
/// headless als SwiftUI-Platzhalter rendern — Snapshot-Tests wären damit
/// unbrauchbar, dieselbe Falle wie bei `Menu` in den Hilfeknöpfen. Zwei feste
/// Reihen zeigen alles gleichzeitig und rendern überall.
public struct LetterRailView: View {
    /// Deutsche Buchstaben plus Umlaute. Kein ẞ: Antworten werden auf SS
    /// normalisiert, ein Knopf dafür würde nur ins Leere führen.
    static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ")

    let onLetter: (Character) -> Void
    let onDelete: () -> Void

    public init(onLetter: @escaping (Character) -> Void,
                onDelete: @escaping () -> Void) {
        self.onLetter = onLetter
        self.onDelete = onDelete
    }

    /// Höchstens so viele Knöpfe je Reihe.
    ///
    /// Zwei Reihen à 15 waren der erste Anlauf und liefen auf dem Fernseher
    /// links und rechts aus dem Bild — im gerenderten Bild begann die Leiste bei
    /// „C". Drei Reihen à 10 passen bei 29 Buchstaben plus Löschen genau auf und
    /// bleiben auch auf schmaleren Flächen innerhalb des Schirms.
    static let columns = 10

    /// Reihen, jede mit `columns` Plätzen. Die letzte Reihe wird mit Leerplätzen
    /// aufgefüllt, damit alle Knöpfe gleich breit bleiben — ohne das würde die
    /// letzte Reihe ihre wenigen Knöpfe über die ganze Breite ziehen.
    private var rows: [[Character?]] {
        var items: [Character?] = Self.letters.map { $0 }
        items.append(nil)                      // Platz für Löschen
        while items.count % Self.columns != 0 { items.append(nil) }
        return stride(from: 0, to: items.count, by: Self.columns)
            .map { Array(items[$0 ..< min($0 + Self.columns, items.count)]) }
    }

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, letter in
                        if let letter {
                            Button {
                                onLetter(letter)
                            } label: {
                                Text(String(letter))
                                    .font(.title3.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .accessibilityLabel(String(letter))
                        } else if isDeleteSlot(row: rowIndex, index: index) {
                            Button(action: onDelete) {
                                Image(systemName: "delete.left")
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .accessibilityLabel(Loc.string("action.delete"))
                        } else {
                            // Leerplatz: hält die Spaltenbreite, ohne fokussierbar
                            // zu sein — sonst liefe die Fernbedienung ins Nichts.
                            Color.clear.frame(maxWidth: .infinity, minHeight: 40)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    /// Der Löschen-Knopf steht auf dem ersten freien Platz nach dem letzten
    /// Buchstaben.
    private func isDeleteSlot(row: Int, index: Int) -> Bool {
        row * Self.columns + index == Self.letters.count
    }
}
