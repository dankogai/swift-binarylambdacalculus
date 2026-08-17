// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BinaryLambdaCalculus",
    // the oldest OS versions whose runtime supports opaque result types
    // (`some Sequence<Bit>`, returned by the output streams); Linux and
    // other non-Darwin platforms are unaffected by this list
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6),
    ],
    products: [
        .library(
            name: "BinaryLambdaCalculus",
            targets: ["BinaryLambdaCalculus"]
        ),
        .executable(
            name: "blc",
            targets: ["blc"]
        ),
    ],
    targets: [
        .target(
            name: "BinaryLambdaCalculus"
        ),
        .executableTarget(
            name: "blc",
            dependencies: ["BinaryLambdaCalculus"]
        ),
        .testTarget(
            name: "BinaryLambdaCalculusTests",
            dependencies: ["BinaryLambdaCalculus"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
