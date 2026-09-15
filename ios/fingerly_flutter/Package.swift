// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "fingerly_flutter",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "fingerly-flutter", targets: ["fingerly_flutter"]),
    ],
    dependencies: [
        // Flutter creates this package beside every plugin package while
        // resolving an application's generated plugin graph.
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // The repository is private and untagged today, so development uses
        // its authenticated main branch. Replace this with `from: "0.1.0"`
        // when the native SDK is published; CocoaPods has the same release
        // boundary through the `Fingerly` dependency below.
        .package(
            name: "Fingerly",
            url: "ssh://git@github.com/fingerly-io/sdk-ios.git",
            branch: "main"
        ),
    ],
    targets: [
        .target(
            name: "fingerly_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "Fingerly", package: "Fingerly"),
            ]
        ),
    ]
)
