// swift-tools-version: 6.2
//
// This manifest builds the portable, Foundation-only core of eXoMAC as a
// standalone Swift package so it can be compiled and tested from the command
// line (and, later, on Linux). The Xcode app target compiles the same files
// directly through its folder-synchronized group, so there is nothing to link.
//
//   swift build          # compiles eXoMAC/Core as the eXoCore module
//   swift test           # runs Tests/eXoCoreTests
//
import PackageDescription

let coreSettings: [SwiftSetting] = [
    // Mirror the app target's "approachable concurrency" settings so that the
    // package build enforces the same isolation rules as the Xcode build.
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "eXoMAC",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "eXoCore", targets: ["eXoCore"]),
    ],
    targets: [
        .target(
            name: "eXoCore",
            path: "eXoMAC/Core",
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "eXoCoreTests",
            dependencies: ["eXoCore"],
            path: "Tests/eXoCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: coreSettings
        ),
    ]
)
