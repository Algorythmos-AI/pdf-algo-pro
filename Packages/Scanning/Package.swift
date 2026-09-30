// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .treatAllWarnings(as: .error),
]

let package = Package(
  name: "Scanning",
  defaultLocalization: "en",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "Scanning", targets: ["Scanning"])
  ],
  dependencies: [
    .package(path: "../Core")
  ],
  targets: [
    .target(
      name: "Scanning",
      dependencies: [.product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "ScanningTests",
      dependencies: ["Scanning", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
