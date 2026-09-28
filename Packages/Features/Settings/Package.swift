// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "Settings",
  defaultLocalization: "en",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "SettingsFeature", targets: ["SettingsFeature"])
  ],
  dependencies: [
    .package(path: "../../Core"),
    .package(path: "../../DesignSystem"),
  ],
  targets: [
    .target(
      name: "SettingsFeature",
      dependencies: [.product(name: "Core", package: "Core"), .product(name: "DesignSystem", package: "DesignSystem")],
      resources: [.process("Resources")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "SettingsFeatureTests",
      dependencies: ["SettingsFeature", .product(name: "CoreTestSupport", package: "Core"), .product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
