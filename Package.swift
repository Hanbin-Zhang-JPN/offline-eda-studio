// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OfflineEDAStudio",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EDACore", targets: ["EDACore"]),
        .executable(name: "EDAStudio", targets: ["EDAStudio"]),
        .executable(name: "eda", targets: ["EDACLI"])
    ],
    targets: [
        .target(name: "EDACore"),
        .executableTarget(name: "EDAStudio", dependencies: ["EDACore"], resources: [.copy("Resources")]),
        .executableTarget(name: "EDACLI", dependencies: ["EDACore"]),
        .executableTarget(name: "EDASelfTests", dependencies: ["EDACore"], path: "Tests/EDACoreTests")
    ]
)
