// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SurfPixel",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SurfPixel", path: "Sources/SurfPixel")
    ]
)
