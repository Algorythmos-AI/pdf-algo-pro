// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .treatAllWarnings(as: .error),
]

let package = Package(
  name: "Core",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "Core", targets: ["Core"]),
    .library(name: "CoreTestSupport", targets: ["CoreTestSupport"]),
    // The identifiers the app sets on its controls and the UI tests find them by: one list for both,
    // generated from design/accessibility-ids.json (docs/testing-strategy.md).
    .library(name: "AccessibilityIDs", targets: ["AccessibilityIDs"]),
  ],
  targets: [
    .target(
      name: "AccessibilityIDs",
      dependencies: [],
      swiftSettings: settings
    ),
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
