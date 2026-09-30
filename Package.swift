// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "URLRouter",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "URLRouter",
            dependencies: ["Yams"],
            path: "Sources/URLRouter"
        ),
        .testTarget(
            name: "URLRouterTests",
            dependencies: ["URLRouter"],
            path: "Tests/URLRouterTests"
        )
    ]
)
