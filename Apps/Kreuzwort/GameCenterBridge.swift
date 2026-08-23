import SwiftUI
import GameServices

// Das Game-Center-Dashboard zu **zeigen** ist plattformabhängig, es zu
// **benutzen** nicht. Deshalb liegt nur dieses Stück hier neben
// PlatformSurface.swift, und GameServices bleibt frei von UI-Frameworks.

#if canImport(UIKit) && !os(watchOS)
import UIKit
import GameKit

@MainActor
enum GameCenterBridge {
    /// Öffnet das Dashboard, wenn es das auf dieser Plattform gibt.
    static func presentDashboard() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let controller = GKGameCenterViewController(state: .dashboard)
        controller.gameCenterDelegate = DismissDelegate.shared
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return }
        root.present(controller, animated: true)
    }

    /// Auf dem Haupt-Aktor isoliert: GameKit ruft das Delegate von dort, und ein
    /// gemeinsam genutztes `shared` ohne Isolierung ist unter Swift 6 zu Recht
    /// ein Fehler — macOS fiel nicht darauf auf, weil dort kein Delegate nötig ist.
    @MainActor
    private final class DismissDelegate: NSObject, GKGameCenterControllerDelegate {
        static let shared = DismissDelegate()
        nonisolated func gameCenterViewControllerDidFinish(
            _ controller: GKGameCenterViewController) {
            Task { @MainActor in controller.dismiss(animated: true) }
        }
    }
}

#elseif canImport(AppKit)
import AppKit
import GameKit

@MainActor
enum GameCenterBridge {
    static func presentDashboard() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        // Auf dem Mac übernimmt der Zugangspunkt das Fenster selbst.
        GKAccessPoint.shared.isActive = true
        GKAccessPoint.shared.trigger(state: .dashboard) {}
    }
}

#else

@MainActor
enum GameCenterBridge {
    static func presentDashboard() {}
}

#endif
