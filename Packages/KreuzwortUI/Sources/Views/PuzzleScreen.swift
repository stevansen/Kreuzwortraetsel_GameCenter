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
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showsClueList) {
            ClueListView(session: session) {
                session.apply(.selectSlot($0))
                showsClueList = false
            }
        }
        .focusable()
        .onKeyPress(characters: .alphanumerics) { press in
            handleCharacter(press.characters)
        }
        .onKeyPress(.leftArrow) { move(.across, false) }
        .onKeyPress(.rightArrow) { move(.across, true) }
        .onKeyPress(.upArrow) { move(.down, false) }
        .onKeyPress(.downArrow) { move(.down, true) }
        .onKeyPress(.space) { session.apply(.toggleDirection); return .handled }
        .onKeyPress(.tab) { session.apply(.nextSlot); return .handled }
        .onKeyPress(.delete) { session.apply(.deleteBackward); return .handled }
        .onAppear { session.start() }
        .onDisappear { session.pause() }
        .onChange(of: session.isSolved) { _, solved in
            if solved, let breakdown = session.breakdown { onSolved(breakdown) }
        }
    }

    private var playArea: some View {
        VStack(spacing: 12) {
            header
            GridView(session: session, capabilities: capabilities) { cell in
                session.apply(.jump(cell))
            }
            .frame(maxHeight: .infinity)
            ClueBarView(session: session,
                        onPrevious: { session.apply(.previousSlot) },
                        onNext: { session.apply(.nextSlot) })
            // Buchstaben auf dem Schirm, wo es keine Tastatur gibt. Ohne diese
            // Leiste ist die App auf dem Fernseher nicht spielbar — die gesamte
            // Eingabe hing an `onKeyPress`, und die Fernbedienung liefert keine
            // Zeichen.
            if capabilities.needsOnScreenLetters {
                // Dieselbe Umwandlung wie bei der Tastatur, damit es nur einen
                // Weg von einem Zeichen zu einem Eintrag gibt.
                LetterRailView(onLetter: { _ = handleCharacter(String($0)) },
                               onDelete: { session.apply(.deleteBackward) })
            }
            controls
        }
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
                Button { showsClueList = true } label: {
                    Label { Text(loc: "action.questions") } icon: { Image(systemName: "list.bullet") }
                }
            }
            Spacer(minLength: 4)
            if session.canRevealLetter {
                Button { session.revealLetter() } label: {
                    Label { Text(loc: "action.revealLetter") } icon: { Image(systemName: "character.magnify") }
                }
            }
            if session.canRevealWord {
                Button { session.revealWord() } label: {
                    Label { Text(loc: "action.revealWord") } icon: { Image(systemName: "text.magnifyingglass") }
                }
            }
            if session.canCheckGrid {
                Button { _ = session.checkGrid() } label: {
                    Label { Text(loc: "action.check") } icon: { Image(systemName: "checkmark.circle") }
                }
            }
            Button { session.apply(.togglePencil) } label: {
                Label { Text(loc: isPencil ? "action.pencilOff" : "action.pencilOn") }
                    icon: { Image(systemName: isPencil ? "pencil.slash" : "pencil") }
            }
        }
        .buttonStyle(.bordered)
        .font(.callout)
        .labelStyle(LabelStyleForSurface(showsTitle: capabilities.hasPointer))
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
