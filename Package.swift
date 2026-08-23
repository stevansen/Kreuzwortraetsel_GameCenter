// swift-tools-version: 6.0
import PackageDescription

// Swift-6-Sprachmodus ist bei tools-version 6.0 Default (strict concurrency).
let strict: [SwiftSetting] = []

let package = Package(
    name: "KreuzwortCore",
    platforms: [.iOS(.v18), .macOS(.v15), .tvOS(.v18)],
    products: [
        .library(name: "PuzzleKit", targets: ["PuzzleKit"]),
        .library(name: "ClueCatalog", targets: ["ClueCatalog"]),
        .library(name: "GameServices", targets: ["GameServices"]),
        .library(name: "SyncKit", targets: ["SyncKit"]),
        .library(name: "KreuzwortUI", targets: ["KreuzwortUI"]),
        .executable(name: "KreuzwortMac", targets: ["KreuzwortMac"]),
        .executable(name: "puzzlegen", targets: ["puzzlegen"]),
        .executable(name: "catalogbuild", targets: ["catalogbuild"]),
        .executable(name: "uishot", targets: ["uishot"]),
    ],
    targets: [
        // MARK: - Kern: keine Apple-Framework-Abhängigkeiten, deterministisch
        .target(
            name: "PuzzleKit",
            path: "Packages/PuzzleKit/Sources",
            swiftSettings: strict
        ),
        .testTarget(
            name: "PuzzleKitTests",
            dependencies: ["PuzzleKit"],
            path: "Packages/PuzzleKit/Tests",
            swiftSettings: strict
        ),

        // MARK: - Katalog: SQLite-I/O, baut daraus ein Lexicon für PuzzleKit
        .target(
            name: "ClueCatalog",
            dependencies: ["PuzzleKit"],
            path: "Packages/ClueCatalog/Sources",
            swiftSettings: strict,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "ClueCatalogTests",
            dependencies: ["ClueCatalog", "PuzzleKit"],
            path: "Packages/ClueCatalog/Tests",
            swiftSettings: strict
        ),

        // MARK: - Plattform-Adapter
        .target(name: "GameServices", dependencies: ["PuzzleKit"],
                path: "Packages/GameServices/Sources", swiftSettings: strict),
        .target(name: "SyncKit", dependencies: ["PuzzleKit"],
                path: "Packages/SyncKit/Sources", swiftSettings: strict),

        // MARK: - Geteilte Oberfläche
        //
        // Enthält SwiftUI-Ansichten und den Spielzustand, aber **keine**
        // Plattformverzweigung: `SurfaceCapabilities` wird von den App-Targets
        // hereingegeben. Ein Test scannt dieses Verzeichnis auf `#if os(`.
        .target(name: "KreuzwortUI", dependencies: ["PuzzleKit"],
                path: "Packages/KreuzwortUI/Sources", swiftSettings: strict),
        .testTarget(name: "KreuzwortUITests", dependencies: ["KreuzwortUI", "PuzzleKit"],
                    path: "Packages/KreuzwortUI/Tests", swiftSettings: strict),

        // MARK: - CLIs
        // MARK: - Lauffähige App
        //
        // macOS-Host für die geteilte Oberfläche. Die Plattformerkennung sitzt
        // hier und nicht in KreuzwortUI: das App-Target ist der einzige Ort, an
        // dem `#if os(...)` seinen Platz hat.
        .executableTarget(name: "KreuzwortMac",
                          dependencies: ["KreuzwortUI", "PuzzleKit", "ClueCatalog"],
                          path: "Apps/KreuzwortMac", swiftSettings: strict),

        .executableTarget(name: "puzzlegen", dependencies: ["PuzzleKit", "ClueCatalog"],
                          path: "Tools/puzzlegen", swiftSettings: strict),
        // Rendert Ansichten headless in PNGs — Grundlage der Snapshot-Tests und
        // die einzige Möglichkeit, eine Oberfläche zu *prüfen* statt nur zu bauen.
        .executableTarget(name: "uishot",
                          dependencies: ["KreuzwortUI", "PuzzleKit", "ClueCatalog"],
                          path: "Tools/uishot", swiftSettings: strict),

        .executableTarget(name: "catalogbuild", dependencies: ["ClueCatalog", "PuzzleKit"],
                          path: "Tools/catalogbuild", swiftSettings: strict),
    ]
)
