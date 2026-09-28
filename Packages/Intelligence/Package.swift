// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
  name: "Intelligence",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "Intelligence", targets: ["Intelligence"])
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
    .testTarget(
      name: "IntelligenceTests",
      dependencies: ["Intelligence", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
