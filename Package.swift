// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fast",
    platforms: [.macOS("15.4")],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.3")
    ],
    targets: [
        .target(name: "YabCoreClient", path: "YabCore/Client/Sources/YabCoreClient",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        // What syncs between your Macs and iPhone, and how two copies of it
        // become one (PLAN-sync.md). No AppKit, no UIKit: the iPhone app
        // takes the same module.
        .target(
            name: "SyncKit",
            path: "Sources/SyncKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The design system: colors, corners, motion, icons, the one
        // button and the keys drawn on it. Nothing in it knows the app;
        // Fast re-exports it (Design.swift), so every file sees it.
        .target(
            name: "YabDesign",
            path: "Sources/YabDesign",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Where the app keeps its things (Store: the folder, the settings, a
        // test run's own of both), one SQLite connection type and the
        // keychain asked without its window. The app and the mail engine
        // both use it.
        .target(
            name: "YabStore",
            path: "Sources/YabStore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The mail engine without a window: Gmail, the store on this Mac,
        // sync, search, the splits, sense, memory, invitations, files. Fast
        // re-exports it (MailCoreEdges.swift), so every file sees it.
        .target(
            name: "MailCore",
            dependencies: ["YabStore"],
            path: "Sources/MailCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // What an update is and how it is put in place, without a window:
        // the feed, when a copy takes a release, the swap of the bundle. The
        // app and the agent that updates it while it is closed share it.
        .target(
            name: "YabUpdate",
            dependencies: ["YabStore"],
            path: "Sources/YabUpdate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // That agent: started by launchd from the app's bundle at login and
        // every four hours, it updates a Yab that isn't open, then quits.
        .executableTarget(
            name: "YabUpdater",
            dependencies: ["YabStore", "YabUpdate"],
            path: "Sources/YabUpdater",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "NativeTextInput",
            path: "Sources/NativeTextInput",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "Fast",
            dependencies: ["SyncKit", "YabDesign", "YabStore", "MailCore", "YabUpdate", "YabCoreClient", "NativeTextInput",
                           .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/Fast",
            // Same reasoning as the canvas app next door: the whole interface is
            // main-thread by nature, and Swift 6's strict isolation buys nothing
            // here but ceremony.
            swiftSettings: [.swiftLanguageMode(.v5)],
            // SwiftPM stamps the binary as built against the deployment
            // target's SDK, and AppKit takes that at its word: every control
            // is drawn the way macOS 15 drew it. Stamped with the SDK it is
            // actually built with, the settings window, menus and alerts get
            // the current look.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "15.4", "-Xlinker", "26.0"])]
        ),
        // What ./bench can't see: the pure parts, parsers and rules, held to
        // fixed inputs. `swift test`. One folder, a file per area.
        .testTarget(
            name: "FastTests",
            dependencies: ["Fast", "SyncKit", "YabDesign", "YabStore", "MailCore", "MailCoreFakes", "YabUpdate"],
            path: "Tests/FastTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Gmail kept in memory and old mail stores, for both test targets.
        .target(
            name: "MailCoreFakes",
            dependencies: ["MailCore"],
            path: "Tests/MailCoreFakes",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The mail engine's own tests: they build MailCore alone, not the app.
        .testTarget(
            name: "MailCoreTests",
            dependencies: ["MailCore", "YabStore", "MailCoreFakes"],
            path: "Tests/MailCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
