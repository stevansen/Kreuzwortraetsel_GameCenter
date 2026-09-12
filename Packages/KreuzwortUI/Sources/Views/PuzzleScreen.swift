import SwiftUI
import PuzzleKit

/// Die Spielansicht: Gitter, aktive Frage, Fragenliste, Hilfen, Abschluss.
///
/// Das Layout richtet sich nach `SurfaceCapabilities`, nicht nach dem
/// Betriebssystem: wo ein Zeiger und Platz vorhanden sind, steht die Fragenliste
/// als Seitenspalte; sonst ist sie ein Sheet und die aktive Frage steht als
/// Leiste unter dem Gitter.
public struct PuzzleScreen: View {
    @State private var session: PuzzleSession
    @State private var showsClueList = false
    private let capabilities: SurfaceCapabilities
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onNextPuzzle: () -> Void
    /// Wird genau einmal gerufen, wenn das Rätsel gelöst ist.
    ///
    /// Ein Callback statt einer Abhängigkeit auf GameServices: die Ansicht muss
    /// nicht wissen, dass es Game Center gibt — sie meldet, dass etwas fertig ist.
    private let onSolved: (ScoreBreakdown) -> Void

    public init(session: PuzzleSession, capabilities: SurfaceCapabilities,
                onSolved: @escaping (ScoreBreakdown) -> Void = { _ in },
                onNextPuzzle: @escaping () -> Void = {}) {
        self._session = State(initialValue: session)
        self.capabilities = capabilities
        self.onSolved = onSolved
        self.onNextPuzzle = onNextPuzzle
    }

    public var body: some View {
        Group {
            if capabilities.showsSideClueList {
                HStack(alignment: .top, spacing: 16) {
                    playArea
                    ClueListView(session: session) { session.apply(.selectSlot($0)) }
                        .frame(width: 300)
                }
            } else {
                playArea
            }
        }
        .padding(16)
        .overlay(alignment: .center) {
            if session.isSolved {
                CompletionView(session: session, onNext: onNextPuzzle)
                    .background(.background.opacity(0.96),
                                in: RoundedRectangle(cornerRadius: 18))
                    .shadow(radius: 20)
                    // „Bewegung reduzieren" ist keine Geschmacksfrage: Skalieren
                    // löst bei vestibulären Beschwerden Schwindel aus. Die
                    // Einblendung bleibt, das Wachsen entfällt.
                    .transition(reduceMotion ? .opacity
                                             : .scale.combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showsClueList) {
            ClueListView(session: session) {
                session.apply(.selectSlot($0))
                showsClueList = false
            }
        }
        // **Nur wo es eine Tastatur gibt** — und zwar gar nicht erst angebaut,
        // nicht bloß auf `false` gesetzt. Siehe `HardwareKeyboardControls`.
        .modifier(HardwareKeyboardControls(
            enabled: capabilities.handlesHardwareKeys,
            onCharacter: { handleCharacter($0) },
            onMove: { move($0, $1) },
            onCommand: { session.apply($0) }))
        .onAppear { session.start() }
        .onDisappear { session.pause() }
        .onChange(of: session.isSolved) { _, solved in
            if solved, let breakdown = session.breakdown { onSolved(breakdown) }
        }
    }

    private var playArea: some View {
        HStack(alignment: .top, spacing: 12) {
            // **Buchstaben als Spalte — nur wo die Höhe knapp ist.**
            //
            // Auf dem Fernseher ist die Breite im Überfluss vorhanden und die
            // Höhe das knappe Maß: unter dem Gitter kostete die Leiste rund
            // 270 pt und drückte die Zellen auf etwa 30 pt. Auf einem Telefon
            // ist es umgekehrt — dort steht sie unten, siehe `spalte`.
            if capabilities.needsOnScreenLetters, capabilities.lettersBesideGrid {
                letterRail(.tall).frame(width: 300)
            }
            spalte
        }
    }

    private var spalte: some View {
        VStack(spacing: 12) {
            header
            GridView(session: session, capabilities: capabilities) { cell in
                session.apply(.jump(cell))
            }
            .frame(maxHeight: .infinity)
            ClueBarView(session: session,
                        onPrevious: { session.apply(.previousSlot) },
                        onNext: { session.apply(.nextSlot) })
            // Buchstaben unter dem Gitter, wo es keine Tastatur gibt und Platz
            // in der Höhe ist — die gewohnte Stelle auf einem Telefon.
            if capabilities.needsOnScreenLetters, !capabilities.lettersBesideGrid {
                letterRail(.wide)
            }
            controls
        }
    }

    /// Dieselbe Umwandlung wie bei der Tastatur, damit es nur einen Weg von
    /// einem Zeichen zu einem Eintrag gibt.
    private func letterRail(_ layout: LetterRailView.Layout) -> some View {
        LetterRailView(layout: layout,
                       onLetter: { _ = handleCharacter(String($0)) },
                       onDelete: { session.apply(.deleteBackward) })
    }

    private var header: some View {
        HStack {
            Text("\(session.puzzle.variant.displayName) · "
                + session.puzzle.difficulty.displayName)
                .font(.headline)
            Spacer()
            Text(timeText).monospacedDigit().foregroundStyle(.secondary)
                .accessibilityLabel(Loc.string("time.elapsed", timeText))
        }
    }

    /// Hilfen als Symbolknöpfe.
    ///
    /// Zwei Fassungen sind hier gescheitert: nebeneinandergestellte Textknöpfe
    /// wurden auf schmalen Flächen abgeschnitten („Buchsta…"), und ein `Menu`
    /// rendert headless als SwiftUI-Platzhalter — damit wäre jeder Snapshot mit
    /// einem gelben Kasten unbrauchbar. Symbole lösen beides und sind auch die
    /// bessere Oberfläche: keine abgeschnittene Beschriftung, kein zusätzlicher
    /// Tap. Die Beschriftung bleibt für VoiceOver erhalten.
    private var controls: some View {
        HStack(spacing: 10) {
            if !capabilities.showsSideClueList {
                control("action.questions", "list.bullet") { showsClueList = true }
            }
            Spacer(minLength: 4)
            if session.canRevealLetter {
                control("action.revealLetter", "character.magnify") { session.revealLetter() }
            }
            if session.canRevealWord {
                control("action.revealWord", "text.magnifyingglass") { session.revealWord() }
            }
            if session.canCheckGrid {
                control("action.check", "checkmark.circle") { _ = session.checkGrid() }
            }
            control(isPencil ? "action.pencilOff" : "action.pencilOn",
                    isPencil ? "pencil.slash" : "pencil") { session.apply(.togglePencil) }
        }
        .buttonStyle(.bordered)
        .font(.callout)
        .labelStyle(LabelStyleForSurface(showsTitle: capabilities.hasPointer))
    }

    /// Ein Hilfeknopf.
    ///
    /// **Die Beschriftung wird ausdrücklich gesetzt.** Vorher trug sie allein
    /// `LabelStyleForSurface`, das den Titel auf schmalen Flächen in ein
    /// verstecktes Overlay legt — gemessen auf dem iPhone hatten daraufhin
    /// **alle fünf Knöpfe eine leere Beschriftung**. Für das Auge war das
    /// unsichtbar, für VoiceOver waren die Knöpfe namenlos, und ein UI-Test
    /// fand sie nicht. Die Darstellung darf entscheiden, ob der Titel zu
    /// sehen ist; ob er *existiert*, darf sie nicht entscheiden.
    private func control(_ key: String, _ symbol: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(loc: key) } icon: { Image(systemName: symbol) }
        }
        .accessibilityLabel(Loc.string(key))
    }

    private var isPencil: Bool {
        session.progress.cells[session.puzzle.size.index(session.caret.cell)].pencil
    }

    private var timeText: String {
        let t = Int(session.elapsedSeconds.rounded())
        return String(t / 60) + ":" + (t % 60 < 10 ? "0" : "") + String(t % 60)
    }

    // MARK: - Tastatur

    private func handleCharacter(_ characters: String) -> KeyPress.Result {
        guard let first = characters.uppercased().first,
              let letter = Alphabet.index(of: first) else { return .ignored }
        session.apply(.enter(letter))
        return .handled
    }

    private func move(_ direction: Direction, _ forward: Bool) -> KeyPress.Result {
        session.apply(.move(direction, forward: forward))
        return .handled
    }
}

/// Tastaturbedienung — angebaut überall **außer** dort, wo sie schadet.
///
/// **Warum ein eigener Modifier.** `onKeyPress` bekommt nur Ereignisse, wenn
/// die Ansicht fokussierbar ist; deshalb hing über dem ganzen Rätselbildschirm
/// ein `focusable`. Auf dem Fernseher war das der Grund, warum die App
/// unbedienbar war: gemessen mit XCUIRemote hatte dort von **62 Knöpfen kein
/// einziger** den Fokus, weder beim Erscheinen noch nach Tastendrücken — der
/// fokussierbare Container über allem nimmt den Teilbaum aus dem Fokussystem.
///
/// `focusable(false)` genügt als Gegenmittel nicht (gemessen: unverändert
/// null fokussierte Knöpfe), und `defaultFocus` auf dem Gitter ebenso wenig.
/// Was hilft, ist den Modifier dort **nicht anzubringen**.
///
/// **Die Bedingung war zuerst `hasHardwareKeyboard` — das war zu streng.**
/// Ob am iPad gerade ein Magic Keyboard steckt, weiß `SurfaceCapabilities`
/// nicht; dort steht immer `false`. Damit verlor das iPad mit Tastatur die
/// Eingabe. Entscheidend ist nicht, ob eine Tastatur da ist, sondern ob der
/// Modifier schadet — und das tut er nur, wo eine Fokus-Engine läuft.
private struct HardwareKeyboardControls: ViewModifier {
    let enabled: Bool
    let onCharacter: (String) -> KeyPress.Result
    let onMove: (Direction, Bool) -> KeyPress.Result
    let onCommand: (GridCommand) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .focusable()
                .onKeyPress(characters: .alphanumerics) { onCharacter($0.characters) }
                .onKeyPress(.leftArrow) { onMove(.across, false) }
                .onKeyPress(.rightArrow) { onMove(.across, true) }
                .onKeyPress(.upArrow) { onMove(.down, false) }
                .onKeyPress(.downArrow) { onMove(.down, true) }
                .onKeyPress(.space) { onCommand(.toggleDirection); return .handled }
                .onKeyPress(.tab) { onCommand(.nextSlot); return .handled }
                .onKeyPress(.delete) { onCommand(.deleteBackward); return .handled }
        } else {
            content
        }
    }
}

/// Zeigt die Beschriftung nur, wo Platz dafür ist — sonst nur das Symbol.
/// Die Beschriftung bleibt in beiden Fällen für VoiceOver vorhanden.
struct LabelStyleForSurface: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            HStack(spacing: 5) {
                configuration.icon
                configuration.title
            }
        } else {
            // Der Titel bleibt im Baum, nur unsichtbar: so liest VoiceOver
            // weiterhin „Prüfen" und nicht „Knopf".
            configuration.icon
                .accessibilityElement(children: .combine)
                .overlay { configuration.title.hidden() }
        }
    }
}
