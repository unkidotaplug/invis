// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Invis",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Invis", targets: ["Invis"])],
    targets: [.executableTarget(name: "Invis", path: "Sources/Invis")]
)
