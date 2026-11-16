// swift-tools-version: 5.9

import Foundation
import PackageDescription

func relativeFrameworkPath(from packageDirectory: String, to target: String) -> String {
    guard target.hasPrefix("/") else { return target }
    let baseParts = packageDirectory.split(separator: "/").map(String.init)
    let targetParts = target.split(separator: "/").map(String.init)
    var common = 0
    while common < baseParts.count,
          common < targetParts.count,
          baseParts[common] == targetParts[common] {
        common += 1
    }
    let ups = Array(repeating: "..", count: baseParts.count - common)
    let downs = Array(targetParts.dropFirst(common))
    let relative = (ups + downs).joined(separator: "/")
    return relative.isEmpty ? "." : relative
}

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let localFrameworkPath: String? = ProcessInfo.processInfo.environment["FINGERLY_XCFRAMEWORK_PATH"]
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .flatMap { $0.isEmpty ? nil : $0 }
    .map { raw in
        let xcframeworkPath = raw.hasSuffix(".zip")
            ? (raw as NSString).deletingLastPathComponent + "/Fingerly.xcframework"
            : raw
        return relativeFrameworkPath(from: packageDirectory, to: xcframeworkPath)
    }

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
    ] + (localFrameworkPath == nil ? [
        // The public binary package, at the same native version the podspec
        // downloads, so both iOS paths ship the same framework.
        .package(url: "https://github.com/fingerly-io/sdk-ios", exact: "0.3.0"),
    ] : []),
    targets: [
        .target(
            name: "fingerly_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                localFrameworkPath == nil
                    ? .product(name: "Fingerly", package: "sdk-ios")
                    : .target(name: "Fingerly"),
            ]
        ),
    ] + (localFrameworkPath.map { path in
        [.binaryTarget(name: "Fingerly", path: path)]
    } ?? [])
)
