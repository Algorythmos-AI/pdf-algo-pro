// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .treatAllWarnings(as: .error),
]

let package = Package(
  name: "Intelligence",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "Intelligence", targets: ["Intelligence"]),
    .library(name: "IntelligenceEvaluation", targets: ["IntelligenceEvaluation"]),
  ],
  dependencies: [
    .package(path: "../Core")
  ],
  targets: [
    .target(
      name: "Intelligence",
      dependencies: [.product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
    .target(
      name: "IntelligenceEvaluation",
      dependencies: ["Intelligence", .product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "IntelligenceTests",
      dependencies: [
        "Intelligence", "IntelligenceEvaluation", .product(name: "CoreTestSupport", package: "Core"),
        .product(name: "Core", package: "Core"),
      ],
      swiftSettings: settings
    ),
  ]
)
