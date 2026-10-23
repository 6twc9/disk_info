// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskInfo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DiskInfo", targets: ["DiskInfo"])
    ],
    targets: [
        .executableTarget(
            name: "DiskInfo",
            path: "Sources/DiskInfo"
        )
    ]
)
