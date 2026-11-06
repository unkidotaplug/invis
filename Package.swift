// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Inviz",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Inviz", targets: ["Inviz"])],
    targets: [.executableTarget(name: "Inviz", path: "Sources/Inviz")]
)
