// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
        .defaultIsolation(MainActor.self),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "Onboarding",
  defaultLocalization: "en",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "OnboardingFeature", targets: ["OnboardingFeature"]),
  ],
  dependencies: [
    .package(path: "../../Core"),
    .package(path: "../../DesignSystem"),
  ],
  targets: [
    .target(
      name: "OnboardingFeature",
      dependencies: [.product(name: "Core", package: "Core"), .product(name: "DesignSystem", package: "DesignSystem")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "OnboardingFeatureTests",
      dependencies: ["OnboardingFeature", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
