import SwiftUI
import PuzzleKit
import KreuzwortUI

/// Der Startbildschirm: Tagesrätsel, Weiterspielen, Varianten- und Stufenwahl.
struct HomeView: View {
    let environment: AppEnvironment
    let onPlay: (Puzzle, PuzzleProgress?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(loc: "home.title").font(.largeTitle.bold())

                if let resumable = environment.resumable {
                    resumeCard(resumable)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(loc: "home.daily").font(.headline)
                    HStack(spacing: 12) {
                        ForEach(PuzzleVariant.allCases, id: \.self) { variant in
                            dailyCard(variant)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
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
            .padding(20)
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity)
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
