// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "Assistant",
  defaultLocalization: "en",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "AssistantFeature", targets: ["AssistantFeature"])
  ],
  dependencies: [
    .package(path: "../../Core"),
    .package(path: "../../DesignSystem"),
  ],
  targets: [
    .target(
      name: "AssistantFeature",
      dependencies: [.product(name: "Core", package: "Core"), .product(name: "DesignSystem", package: "DesignSystem")],
      resources: [.process("Resources")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "AssistantFeatureTests",
      dependencies: ["AssistantFeature", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
