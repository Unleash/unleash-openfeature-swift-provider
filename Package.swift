// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UnleashOpenFeatureSwiftProvider",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "UnleashOpenFeatureSwiftProvider",
            targets: ["UnleashOpenFeatureSwiftProvider"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/open-feature/swift-sdk", from: "0.5.0"),
        // TEMPORARY: the sdkFlavor client options aren't in a released unleash-ios-sdk yet.
        // Track the SDK feature branch so it resolves in CI too; bump to the published version once merged.
        .package(url: "https://github.com/Unleash/unleash-ios-sdk", branch: "feat/sdk-flavor-metadata"),
    ],
    targets: [
        .target(
            name: "UnleashOpenFeatureSwiftProvider",
            dependencies: [
                .product(name: "OpenFeature", package: "swift-sdk"),
                .product(name: "UnleashProxyClientSwift", package: "unleash-ios-sdk"),
            ]
        ),
        .testTarget(
            name: "UnleashOpenFeatureSwiftProviderTests",
            dependencies: ["UnleashOpenFeatureSwiftProvider"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
