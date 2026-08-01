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
        .testTarget(
            name: "AutoMAAKitTests",
            dependencies: ["AutoMAAKit"]
        ),
    ]
)
