// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
  name: "Telemetry",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "Telemetry", targets: ["Telemetry"])
  ],
  dependencies: [
    .package(path: "../Core")
  ],
  targets: [
    .target(
      name: "Telemetry",
      dependencies: [.product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "TelemetryTests",
      dependencies: ["Telemetry", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
