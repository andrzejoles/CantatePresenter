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
        .target(
            name: "CantatePresenterCore",
            path: "Sources/CantatePresenterCore"
        ),
        .executableTarget(
            name: "CantatePresenter",
            dependencies: ["CantatePresenterCore"],
            path: "Sources/CantatePresenter"
        ),
        .testTarget(
            name: "CantatePresenterCoreTests",
            dependencies: ["CantatePresenterCore"],
            path: "Tests/CantatePresenterCoreTests"
        )
    ]
)
