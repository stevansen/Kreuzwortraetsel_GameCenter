// swift-tools-version: 6.0
import PackageDescription

// Swift-6-Sprachmodus ist bei tools-version 6.0 Default (strict concurrency).
let strict: [SwiftSetting] = []

let package = Package(
    name: "KreuzwortCore",
    platforms: [.iOS(.v18), .macOS(.v15), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "PuzzleKit", targets: ["PuzzleKit"]),
        .library(name: "ClueCatalog", targets: ["ClueCatalog"]),
        .library(name: "GameServices", targets: ["GameServices"]),
        .library(name: "SyncKit", targets: ["SyncKit"]),
        .executable(name: "puzzlegen", targets: ["puzzlegen"]),
        .executable(name: "catalogbuild", targets: ["catalogbuild"]),
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

        // MARK: - CLIs
        .executableTarget(name: "puzzlegen", dependencies: ["PuzzleKit", "ClueCatalog"],
                          path: "Tools/puzzlegen", swiftSettings: strict),
        .executableTarget(name: "catalogbuild", dependencies: ["ClueCatalog", "PuzzleKit"],
                          path: "Tools/catalogbuild", swiftSettings: strict),
    ]
)
