// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SystemSentinel",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "SystemSentinel",
            targets: ["main"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "main",
            dependencies: [],
            path: "Sources"),
        .testTarget(
            name: "SystemSentinelTests",
            dependencies: ["main"],
            path: "Tests/SystemSentinelTests")
    ]
)
