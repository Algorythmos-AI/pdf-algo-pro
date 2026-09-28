// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "Core",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "Core", targets: ["Core"]),
    .library(name: "CoreTestSupport", targets: ["CoreTestSupport"]),
  ],
  targets: [
    .target(
      name: "Core",
      dependencies: [],
      swiftSettings: settings
    ),
    .target(
      name: "CoreTestSupport",
      dependencies: ["Core"],
      swiftSettings: settings
    ),
    .testTarget(
      name: "CoreTests",
      dependencies: ["Core", "CoreTestSupport"],
      swiftSettings: settings
    ),
  ]
)
