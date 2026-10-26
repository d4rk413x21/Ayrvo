// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Ayrvo",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Ayrvo", targets: ["Ayrvo"]),
        .executable(name: "zoom-info", targets: ["zoom-info"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7"),
    ],
    targets: [
        // Tiny ObjC shim whose sole job is to run an AVAudioNode tap-install (and
        // similar AVF calls) inside an @try/@catch. Swift's `do/catch` cannot catch
        // ObjC NSExceptions, so an AVAudioFormat mismatch during a live route change
        // (e.g. plugging in Bluetooth headphones mid-recording) raises through the
        // ObjC runtime and becomes SIGABRT, killing the app. This wraps it instead.
        .target(
            name: "ExceptionCatch",
            path: "Sources/ExceptionCatch",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Ayrvo",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                "ExceptionCatch",
            ],
            path: "Sources/Ayrvo",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "zoom-info",
            path: "Sources/ZoomInfo",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AyrvoTests",
            dependencies: ["Ayrvo"],
            path: "Tests/AyrvoTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
