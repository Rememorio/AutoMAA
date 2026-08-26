// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AutoMAA",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AutoMAAKit", targets: ["AutoMAAKit"]),
        .executable(name: "AutoMAA", targets: ["AutoMAA"]),
        .executable(name: "AutoMAARunner", targets: ["AutoMAARunner"]),
        .executable(name: "AutoMAAResourceProbe", targets: ["AutoMAAResourceProbe"]),
        .executable(name: "AutoMAAUpdater", targets: ["AutoMAAUpdater"]),
    ],
    targets: [
        .target(
            name: "AutoMAAKit",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .executableTarget(
            name: "AutoMAA",
            dependencies: ["AutoMAAKit"]
        ),
        .executableTarget(
            name: "AutoMAARunner",
            dependencies: ["AutoMAAKit"]
        ),
        .executableTarget(
            name: "AutoMAAResourceProbe",
            dependencies: ["AutoMAAKit"]
        ),
        .executableTarget(
            name: "AutoMAAUpdater",
            dependencies: ["AutoMAAKit"]
        ),
        .testTarget(
            name: "AutoMAAKitTests",
            dependencies: ["AutoMAAKit"]
        ),
        .testTarget(
            name: "AutoMAATests",
            dependencies: ["AutoMAA"]
        ),
    ]
)
