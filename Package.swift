// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiftKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // No GRDB, no database files: the LIFT widget extension links this
        // one, and it must stay light enough for a widget's memory budget.
        .library(name: "LiftCore", targets: ["LiftCore"]),
        // GRDB plus 2.3 MB of reference data. Apps only.
        .library(name: "LiftReference", targets: ["LiftReference"]),
        // Offline street-map tiles: pure maths and a GRDB-backed store. No UI.
        .library(name: "LiftMapCore", targets: ["LiftMapCore"]),
        // The route over downloaded streets, and the Maps settings. MapLibre,
        // iOS only. Apps only: never a widget or a share extension.
        .library(name: "LiftMap", targets: ["LiftMap"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution", exact: "6.31.0"),
    ],
    targets: [
        .target(name: "LiftCore"),
        .target(
            name: "LiftReference",
            dependencies: [
                "LiftCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                .copy("Resources/food.db"),
                .copy("Resources/exercises.db"),
                .copy("Resources/recipes.db"),
            ]
        ),
        .target(
            name: "LiftMapCore",
            dependencies: [
                "LiftCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            // Not "Resources": a top-level Resources folder makes an iOS
            // resource bundle look like a macOS one, and codesign refuses it.
            resources: [.copy("MapFiles")]
        ),
        .target(
            name: "LiftMap",
            dependencies: [
                "LiftMapCore",
                "LiftCore",
                // iOS only, so `swift build` and `swift test` on a Mac still
                // build; there RouteMap draws the plain line.
                .product(name: "MapLibre", package: "maplibre-gl-native-distribution",
                         condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "LiftCoreTests",
            dependencies: ["LiftCore"],
            // Written by other implementations (LIFT web), copied in verbatim.
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "LiftReferenceTests", dependencies: ["LiftReference"]),
        .testTarget(name: "LiftMapCoreTests", dependencies: ["LiftMapCore", "LiftCore"]),
        .testTarget(name: "LiftMapTests", dependencies: ["LiftMap", "LiftMapCore", "LiftCore"]),
    ]
)
