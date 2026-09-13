// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "badele_flutter",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "badele-flutter", targets: ["badele_flutter"]),
    ],
    dependencies: [
        // Flutter creates this package beside every plugin package while
        // resolving an application's generated plugin graph.
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // The repository is private and untagged today, so development uses
        // its authenticated main branch. Replace this with `from: "0.1.0"`
        // when the native SDK is published; CocoaPods has the same release
        // boundary through the `Badele` dependency below.
        .package(
            name: "Badele",
            url: "ssh://git@github.com/badele-io/sdk-ios.git",
            branch: "main"
        ),
    ],
    targets: [
        .target(
            name: "badele_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "Badele", package: "Badele"),
            ]
        ),
    ]
)
