import SwiftUI
import PuzzleKit
import KreuzwortUI

/// Der Startbildschirm: Tagesrätsel, Weiterspielen, Varianten- und Stufenwahl.
struct HomeView: View {
    let environment: AppEnvironment
    let capabilities: SurfaceCapabilities
    let onPlay: (Puzzle, PuzzleProgress?) -> Void

    /// Maße nach Betrachtungsabstand.
    ///
    /// Die feste Breite von 560 Punkten war auf dem Fernseher der Fehler: aus
    /// drei Metern eine schmale Spalte am linken Rand, und die Sprachnamen im
    /// Auswahlfeld abgeschnitten („Syste…", „Deuts…"). Der Abstand wächst
    /// mit, weil die Fokus-Engine die gewählte Kachel **vergrößert** — mit 22
    /// Punkten schob sie sich über die Überschrift darüber.
    private var columnWidth: Double { capabilities.viewingDistance == .far ? 1100 : 560 }
    private var sectionSpacing: Double { capabilities.viewingDistance == .far ? 44 : 22 }
    /// Fernseher überscannen: Inhalt nicht an den Rand legen.
    private var outerPadding: Double { capabilities.viewingDistance == .far ? 60 : 20 }
    /// Abstand zwischen Überschrift und Inhalt einer Abteilung. Auf dem
    /// Fernseher hebt die Fokus-Engine die gewählte Kachel nach oben an; mit 8
    /// Punkten schob sie sich über die Überschrift „Tagesrätsel".
    private var headingSpacing: Double { capabilities.viewingDistance == .far ? 26 : 8 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                Text(loc: "home.title").font(.largeTitle.bold())

                statsRow

                if let resumable = environment.resumable {
                    resumeCard(resumable)
                }

                VStack(alignment: .leading, spacing: headingSpacing) {
                    Text(loc: "home.daily").font(.headline)
                    HStack(spacing: 12) {
                        ForEach(PuzzleVariant.allCases, id: \.self) { variant in
                            dailyCard(variant)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: headingSpacing) {
                    Text(loc: "home.newPuzzle").font(.headline)
                    Picker(Loc.string("home.variant"),
                           selection: Binding(get: { environment.variant },
                                              set: { environment.variant = $0 })) {
                        ForEach(PuzzleVariant.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(Loc.string("home.difficulty"),
                           selection: Binding(get: { environment.difficulty },
                                              set: { environment.difficulty = $0 })) {
                        ForEach(Difficulty.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button { start(daily: false) } label: {
                        Text(loc: "home.start").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                languagePicker
            }
            .padding(outerPadding)
            .frame(maxWidth: columnWidth)
        }
        .frame(maxWidth: .infinity)
    }

    /// Punkte und Serie kommen aus dem lokalen Profil, nicht aus Game Center —
    /// deshalb stehen sie auch ohne Anmeldung da.
    private var statsRow: some View {
        HStack(spacing: 14) {
            stat("home.points", "\(environment.profile.points.total)")
            stat("home.solved", "\(environment.profile.solved.total)")
            stat("home.streak", "\(environment.currentStreak)")
            Spacer(minLength: 0)
            if environment.gameCenterAvailable {
                Button { GameCenterBridge.presentDashboard() } label: {
                    Label { Text(loc: "home.gameCenter") }
                        icon: { Image(systemName: "gamecontroller") }
                }
                .buttonStyle(.bordered)
            } else if environment.pendingSubmissions > 0 {
                // Ehrlich statt still: die Punkte sind gezählt, sie warten nur.
                Label { Text(loc: "home.pending") }
                    icon: { Image(systemName: "arrow.up.circle") }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(loc: key).font(.caption2).foregroundStyle(.secondary)
        }
        // Ohne Zusammenfassung liest VoiceOver „0", „0", „0", „Punkte",
        // „Gelöst", „Serie" — sechs Elemente, aus denen sich nicht erschließen
        // lässt, welche Zahl zu welchem Wort gehört.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Loc.string(key)): \(value)")
    }

    private func resumeCard(_ progress: PuzzleProgress) -> some View {
        Button { resume(progress) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc: "home.resume").font(.caption).foregroundStyle(.secondary)
                Text("\(progress.variant.displayName) · \(progress.difficulty.displayName)")
                    .font(.headline)
                // Der Anteil kommt aus dem Spielstand, nicht aus dem Rätsel: das
                // Gitter ist zu diesem Zeitpunkt noch nicht erzeugt.
                ProgressView(value: progress.completion(letterCells: max(progress.cells.count, 1)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Loc.string(
                "home.resume.accessibility",
                progress.variant.displayName, progress.difficulty.displayName,
                Int((progress.completion(letterCells: max(progress.cells.count, 1)) * 100)
                    .rounded())))
            .padding(14)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func dailyCard(_ variant: PuzzleVariant) -> some View {
        Button {
            environment.variant = variant
            start(daily: true)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(variant.displayName).font(.subheadline.weight(.semibold))
                Text(loc: "home.dailyHint").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Die Kachel ist ein Knopf; VoiceOver soll den Zweck ansagen und
            // nicht zwei Textzeilen hintereinander.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Loc.string("home.daily.accessibility",
                                           variant.displayName))
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var languagePicker: some View {
        Picker(Loc.string("home.language"),
               selection: Binding(get: { environment.language ?? "system" },
                                  set: { environment.language = $0 == "system" ? nil : $0 })) {
            Text(loc: "home.languageSystem").tag("system")
            ForEach(Loc.availableLanguages, id: \.self) { code in
                Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
            }
        }
    }

    private func start(daily: Bool) {
        guard let puzzle = try? (daily ? environment.dailyPuzzle() : environment.newPuzzle())
        else { return }
        onPlay(puzzle, environment.store?.load(puzzleID: puzzle.id))
    }

    private func resume(_ progress: PuzzleProgress) {
        guard let puzzle = try? environment.restore(progress) else { return }
        onPlay(puzzle, progress)
    }
}
