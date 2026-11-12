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
        // The public binary package, at the same native version the podspec
        // downloads, so both iOS paths ship the same framework.
        .package(url: "https://github.com/fingerly-io/sdk-ios", exact: "0.2.0"),
    ],
    targets: [
        .target(
            name: "fingerly_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "Fingerly", package: "sdk-ios"),
            ]
        ),
    ]
)
