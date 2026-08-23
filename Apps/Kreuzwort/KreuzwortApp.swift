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

    private var capabilities: SurfaceCapabilities {
        #if !os(macOS) && !os(tvOS)
        PlatformSurface.capabilities(compact: sizeClass == .compact)
        #else
        PlatformSurface.capabilities(compact: false)
        #endif
    }

    var body: some View {
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
                    // Verbuchen, sobald gelöst: Profil, Achievements, Leaderboards.
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
            } else {
                HomeView(environment: environment) { puzzle, progress in
                    session = PuzzleSession(puzzle: puzzle, progress: progress,
                                            deviceID: environment.store?.deviceID ?? 1)
                }
            }
        }
    }
}
