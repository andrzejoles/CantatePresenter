// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CantatePresenter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CantatePresenter", targets: ["CantatePresenter"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CantatePresenter",
            path: "Sources/CantatePresenter"
        )
    ]
)
