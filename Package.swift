// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolishPop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PolishPop", targets: ["PolishPop"])
    ],
    targets: [
        .executableTarget(
            name: "PolishPop",
            path: "Sources/PolishPop"
        )
    ],
    swiftLanguageModes: [.v6]
)
