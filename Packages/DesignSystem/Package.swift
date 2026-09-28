// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
        .defaultIsolation(MainActor.self),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "DesignSystem",
  defaultLocalization: "en",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
  ],
  dependencies: [
    .package(path: "../Core"),
  ],
  targets: [
    .target(
      name: "DesignSystem",
      dependencies: [.product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "DesignSystemTests",
      dependencies: ["DesignSystem", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
