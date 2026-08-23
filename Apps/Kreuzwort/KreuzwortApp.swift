import SwiftUI
import PuzzleKit
import KreuzwortUI

@main
struct KreuzwortApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .task { await environment.load() }
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}

struct RootView: View {
    let environment: AppEnvironment
    @State private var session: PuzzleSession?
    #if !os(macOS) && !os(tvOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// Handoff-Kennung. Muss mit `NSUserActivityTypes` in der Info.plist
    /// übereinstimmen, sonst nimmt das System die Aktivität nicht an.
    static let activityType = "com.kreuzwort.app.puzzle"

    private var capabilities: SurfaceCapabilities {
        #if !os(macOS) && !os(tvOS)
        PlatformSurface.capabilities(compact: sizeClass == .compact)
        #else
        PlatformSurface.capabilities(compact: false)
        #endif
    }

    var body: some View {
        content
            // Deep Link: kreuzwort://p/<variante>/<stufe>/<seed>. Weil ein Rätsel
            // vollständig durch seinen Seed beschrieben ist, ist „schick mir
            // dieses Rätsel" ein Link und kein Datentransfer.
            .onOpenURL { url in
                guard let puzzle = environment.puzzle(fromURL: url) else { return }
                open(puzzle)
            }
            // Handoff ist der schnelle Pfad, CloudKit der verlässliche: das
            // Rätsel auf dem iPad weiterzuspielen soll nicht auf eine
            // Synchronisierung warten.
            .onContinueUserActivity(Self.activityType) { activity in
                guard let payload = activity.userInfo as? [String: String],
                      let link = PuzzleLink(activityPayload: payload),
                      let puzzle = try? environment.puzzle(from: link) else { return }
                open(puzzle)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch environment.state {
        case .loading:
            ProgressView { Text(loc: "app.loading") }.padding(40)

        case .failed(let message):
            VStack(spacing: 10) {
                Text(loc: "app.loadFailed").font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button { Task { await environment.load() } } label: {
                    Text(loc: "app.retry")
                }
            }
            .padding(30)

        case .ready:
            if let session {
                PuzzleScreen(session: session, capabilities: capabilities,
                             onSolved: { breakdown in
                    Task {
                        await environment.recordCompletion(
                            puzzle: session.puzzle, progress: session.progress,
                            breakdown: breakdown, isDaily: false)
                    }
                    environment.persist(session.progress)
                }, onNextPuzzle: {
                    environment.persist(session.progress)
                    self.session = nil
                })
                .id(session.puzzle.id)
                .onDisappear { environment.persist(session.progress) }
                .userActivity(Self.activityType) { activity in
                    // Der Nutzlast genügt der Seed — das Gitter entsteht auf dem
                    // anderen Gerät neu.
                    activity.title = session.puzzle.variant.displayName
                    activity.userInfo = PuzzleLink(puzzle: session.puzzle).activityPayload
                    activity.isEligibleForHandoff = true
                    activity.webpageURL = URL(
                        string: PuzzleLink(puzzle: session.puzzle).universalURLString)
                }
            } else {
                HomeView(environment: environment) { puzzle, progress in
                    session = PuzzleSession(puzzle: puzzle, progress: progress,
                                            deviceID: environment.store?.deviceID ?? 1)
                }
            }
        }
    }

    private func open(_ puzzle: Puzzle) {
        session = PuzzleSession(puzzle: puzzle,
                                progress: environment.store?.load(puzzleID: puzzle.id),
                                deviceID: environment.store?.deviceID ?? 1)
    }
}
