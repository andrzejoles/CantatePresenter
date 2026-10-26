// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CantatePresenter",
    defaultLocalization: "pl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CantatePresenter", targets: ["CantatePresenter"])
    ],
    dependencies: [
        // Automatyczne aktualizacje (decyzja właściciela 2026-10-16). Jedyna zależność; wersja przypięta.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(
            name: "CantatePresenterCore",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/CantatePresenterCore",
            resources: [.process("Resources")]
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
