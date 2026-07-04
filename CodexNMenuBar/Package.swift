// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexNMenuBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexNMenuBar", targets: ["CodexNMenuBar"])
    ],
    targets: [
        .target(name: "CodexNCore"),
        .executableTarget(
            name: "CodexNMenuBar",
            dependencies: ["CodexNCore"]
        ),
        .executableTarget(
            name: "CodexNCoreTestRunner",
            dependencies: ["CodexNCore"]
        )
    ]
)
