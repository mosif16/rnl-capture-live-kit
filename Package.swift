// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CaptureLiveKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CaptureLiveKit",
            targets: ["CaptureLiveKit"]
        )
    ],
    targets: [
        .target(
            name: "CaptureLiveKit"
        ),
        .testTarget(
            name: "CaptureLiveKitTests",
            dependencies: ["CaptureLiveKit"]
        )
    ]
)
