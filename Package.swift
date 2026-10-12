// swift-tools-version: 6.2
//
// This manifest builds the portable, Foundation-only core of eXoMAC as the
// eXoCore library, plus the two vendored C decoders it uses for menu music.
// The Xcode app target links the eXoCore product of this package (added as a
// local package dependency), and the tests run from the command line:
//
//   swift build          # eXoCore and the vendored C targets
//   swift test           # runs Tests/eXoCoreTests
//
// Vendored C code lives in its own target under Sources/ with the upstream
// LICENSE and a VENDOR.md note; see CLAUDE.md for the rules.
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
        .library(name: "eXoCore", targets: ["eXoCore"])
    ],
    targets: [
        // stb_vorbis: Ogg Vorbis decoder (public domain / MIT), one C file.
        .target(name: "CStbVorbis"),
        // libxmp-lite: MOD, S3M, XM and IT module player (MIT).
        .target(
            name: "CXmpLite",
            cSettings: [.define("LIBXMP_CORE_PLAYER"), .define("LIBXMP_STATIC")]
        ),
        .target(
            name: "eXoCore",
            dependencies: ["CStbVorbis", "CXmpLite"],
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
