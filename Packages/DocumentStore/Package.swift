// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
  name: "DocumentStore",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "DocumentStore", targets: ["DocumentStore"])
  ],
  dependencies: [
    .package(path: "../Core")
  ],
  targets: [
    .target(
      name: "DocumentStore",
      dependencies: [.product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "DocumentStoreTests",
      dependencies: ["DocumentStore", .product(name: "CoreTestSupport", package: "Core"), .product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
