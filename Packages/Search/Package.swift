// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
  name: "Search",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "Search", targets: ["Search"])
  ],
  dependencies: [
    .package(path: "../Core")
  ],
  targets: [
    .target(
      name: "Search",
      dependencies: [.product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "SearchTests",
      dependencies: ["Search", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
