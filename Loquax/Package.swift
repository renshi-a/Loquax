// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Loquax",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "Loquax",
            targets: ["Loquax"]),
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "Loquax",
            dependencies: [
                .product(name: "Starscream", package: "Starscream")
            ]
        )
    ]
)
