// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swisswitch",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "SwisswitchCore"),
        .executableTarget(name: "swisswitch", dependencies: ["SwisswitchCore"]),
        .testTarget(name: "SwisswitchCoreTests", dependencies: ["SwisswitchCore"]),
    ]
)
