// swift-tools-version:6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "FlickCore", path: "Sources/FlickCore", swiftSettings: v5),
        .executableTarget(
            name: "Flick",
            dependencies: ["FlickCore"],
            path: "Sources/Flick",
            swiftSettings: v5,
            linkerSettings: [.linkedFramework("ScreenCaptureKit"), .linkedFramework("Carbon")]
        ),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"], path: "Tests/FlickCoreTests", swiftSettings: v5),
    ]
)
