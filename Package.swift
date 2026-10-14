// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HolyricsMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HolyricsMac", targets: ["HolyricsMac"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "HolyricsMac",
            path: "Sources/HolyricsMac"
        )
    ]
)
