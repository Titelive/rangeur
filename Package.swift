// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rangeur",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Rangeur",
            path: "Sources/Rangeur"
        )
    ]
)
