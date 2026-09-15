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
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
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
            ]
        ),
        .testTarget(name: "LiftCoreTests", dependencies: ["LiftCore"]),
        .testTarget(name: "LiftReferenceTests", dependencies: ["LiftReference"]),
    ]
)
