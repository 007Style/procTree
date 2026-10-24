// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "procTree",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "procTree",
            targets: ["procTree"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "procTree",
            dependencies: [],
            path: "Sources/procTree"
        ),
    ]
)
