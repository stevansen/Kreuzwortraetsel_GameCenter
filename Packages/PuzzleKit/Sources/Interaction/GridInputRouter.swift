/// Ein semantisches Eingabekommando.
///
/// **Warum diese Zwischenschicht.** Die Zielplattformen haben drei sehr
/// verschiedene Eingabemodelle: Touch mit Bildschirmtastatur, Hardware-Tastatur
/// und Fokus-Fernbedienung. Alle drei münden hier in dieselben Kommandos, und
/// die Spiellogik sieht nur die Kommandos. Ohne diese Schicht wandert
/// Plattformwissen in die Ansichten, und `#if os(...)` beginnt zu wuchern.
public enum GridCommand: Equatable, Sendable {
    /// Cursor um eine Zelle bewegen. Nicht-Buchstabenzellen werden übersprungen.
    case move(Direction, forward: Bool)
    /// Zwischen waagrecht und senkrecht wechseln.
    case toggleDirection
    /// Buchstabe eintragen (und weiterrücken).
    case enter(Letter)
    /// Aktuelle Zelle leeren, Cursor bleibt.
    case clear
    /// Zurück und leeren — das Verhalten der Rücktaste.
    case deleteBackward
    /// Direkt zu einer Zelle springen (Tap, Klick, Fokus).
    case jump(Cell)
    /// Zum nächsten bzw. vorigen Wort. `Tab` und `Shift-Tab`.
    case nextSlot
    case previousSlot
    /// Ein Wort direkt anspringen (Tap auf die Frageliste oder eine Fragezelle).
    case selectSlot(Int)
    /// Unsicherheits-Markierung der aktuellen Zelle umschalten (Pencil-Modus).
    case togglePencil
}

/// Wendet Kommandos auf Cursor und Spielstand an.
///
/// Bewusst in `PuzzleKit` und nicht in der UI-Schicht: das hier ist reine Logik
/// ohne SwiftUI, auf jeder Plattform testbar und von allen Oberflächen nutzbar —
/// auch von der Fernbedienungssteuerung auf tvOS, die gar keinen Cursor im
/// üblichen Sinn hat.
public struct GridInputRouter: Sendable {
    public let navigation: GridNavigation
    /// Rückt der Cursor nach dem Eintragen automatisch weiter?
    public let advancesAfterEntry: Bool

    public init(navigation: GridNavigation, advancesAfterEntry: Bool = true) {
        self.navigation = navigation
        self.advancesAfterEntry = advancesAfterEntry
    }

    public func apply(_ command: GridCommand, caret: Caret,
                      progress: inout PuzzleProgress) -> Caret {
        switch command {
        case .move(let direction, let forward):
            return moved(caret, along: direction, forward: forward)

        case .toggleDirection:
            let wanted = caret.direction.opposite
            guard navigation.slot(at: caret.cell, direction: wanted) != nil else { return caret }
            return Caret(cell: caret.cell, direction: wanted)

        case .enter(let letter):
            guard navigation.isLetter(caret.cell) else { return caret }
            let index = navigation.size.index(caret.cell)
            let pencil = progress.cells[index].pencil
            progress.set(letter, at: index, pencil: pencil)
            guard advancesAfterEntry else { return caret }
            return advancedWithinSlot(caret)

        case .clear:
            guard navigation.isLetter(caret.cell) else { return caret }
            progress.set(nil, at: navigation.size.index(caret.cell))
            return caret

        case .deleteBackward:
            guard navigation.isLetter(caret.cell) else { return caret }
            let index = navigation.size.index(caret.cell)
            if progress.letter(at: index) != nil {
                // Belegte Zelle: leeren und stehen bleiben — so erwartet man es
                // beim Korrigieren eines einzelnen Buchstabens.
                progress.set(nil, at: index)
                return caret
            }
            let back = moved(caret, along: caret.direction, forward: false)
            if back != caret { progress.set(nil, at: navigation.size.index(back.cell)) }
            return back

        case .jump(let cell):
            guard navigation.isLetter(cell),
                  let direction = navigation.viableDirection(at: cell,
                                                             preferring: caret.direction)
            else { return caret }
            // Erneuter Tap auf die aktive Zelle wechselt die Richtung — das ist
            // die etablierte Geste und spart einen eigenen Knopf.
            if cell == caret.cell,
               navigation.slot(at: cell, direction: caret.direction.opposite) != nil {
                return Caret(cell: cell, direction: caret.direction.opposite)
            }
            return Caret(cell: cell, direction: direction)

        case .nextSlot:
            return slotStep(caret, offset: 1, progress: progress)

        case .previousSlot:
            return slotStep(caret, offset: -1, progress: progress)

        case .selectSlot(let id):
            guard let entry = navigation.entry(id) else { return caret }
            let target = firstEmptyOrFirst(of: id, progress: progress) ?? entry.slot.start
            return Caret(cell: target, direction: entry.slot.direction)

        case .togglePencil:
            guard navigation.isLetter(caret.cell) else { return caret }
            let index = navigation.size.index(caret.cell)
            let cell = progress.cells[index]
            progress.set(cell.letter, at: index, pencil: !cell.pencil)
            return caret
        }
    }

    // MARK: - Bewegung

    /// Nächste Buchstabenzelle in dieser Richtung. Nicht-Buchstabenzellen werden
    /// übersprungen; am Rand bleibt der Cursor stehen.
    func moved(_ caret: Caret, along direction: Direction, forward: Bool) -> Caret {
        let d = direction.delta
        let step = forward ? 1 : -1
        var next = caret.cell
        while true {
            next = next.offset(d.dr * step, d.dc * step)
            guard navigation.size.contains(next) else { return caret }
            if navigation.isLetter(next) {
                let wanted = navigation.viableDirection(at: next, preferring: direction)
                    ?? caret.direction
                return Caret(cell: next, direction: wanted)
            }
        }
    }

    /// Nach dem Eintragen: zur nächsten **leeren** Zelle im selben Wort, sonst
    /// eine Zelle weiter, sonst stehen bleiben.
    func advancedWithinSlot(_ caret: Caret) -> Caret {
        guard let slotID = navigation.slot(at: caret.cell, direction: caret.direction)
        else { return caret }
        let cells = navigation.cells(ofSlot: slotID)
        guard let position = cells.firstIndex(of: caret.cell) else { return caret }
        if position + 1 < cells.count {
            return Caret(cell: cells[position + 1], direction: caret.direction)
        }
        return caret
    }

    private func firstEmptyOrFirst(of slotID: Int, progress: PuzzleProgress) -> Cell? {
        let cells = navigation.cells(ofSlot: slotID)
        return cells.first { progress.letter(at: navigation.size.index($0)) == nil }
            ?? cells.first
    }

    private func slotStep(_ caret: Caret, offset: Int, progress: PuzzleProgress) -> Caret {
        let slots = navigation.orderedSlots
        guard !slots.isEmpty else { return caret }
        let current = navigation.slot(at: caret.cell, direction: caret.direction)
        let index = current.flatMap { slots.firstIndex(of: $0) } ?? 0
        let next = ((index + offset) % slots.count + slots.count) % slots.count
        let id = slots[next]
        guard let entry = navigation.entry(id) else { return caret }
        let target = firstEmptyOrFirst(of: id, progress: progress) ?? entry.slot.start
        return Caret(cell: target, direction: entry.slot.direction)
    }
}
