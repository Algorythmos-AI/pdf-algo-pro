// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .treatAllWarnings(as: .error),
]

let package = Package(
  name: "Paywall",
  defaultLocalization: "en",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "PaywallFeature", targets: ["PaywallFeature"])
  ],
  dependencies: [
    .package(path: "../../Core"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../Commerce"),
  ],
  targets: [
    .target(
      name: "PaywallFeature",
      dependencies: [
        .product(name: "Core", package: "Core"), .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "Commerce", package: "Commerce"),
      ],
      resources: [.process("Resources")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "PaywallFeatureTests",
      dependencies: [
        "PaywallFeature", .product(name: "CoreTestSupport", package: "Core"),
        .product(name: "Core", package: "Core"), .product(name: "Commerce", package: "Commerce"),
        .product(name: "CommerceTestSupport", package: "Commerce"),
      ],
      swiftSettings: settings
    ),
  ]
)
