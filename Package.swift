// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCStatus",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CCStatus",
            path: "Sources/CCStatus",
            exclude: ["Info.plist"]
        )
    ]
)
