// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .treatAllWarnings(as: .error),
]

let package = Package(
  name: "PDFEngine",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "PDFEngine", targets: ["PDFEngine"]),
    .library(name: "PDFEngineTestSupport", targets: ["PDFEngineTestSupport"]),
  ],
  dependencies: [
    .package(path: "../Core")
  ],
  targets: [
    .target(
      name: "PDFEngine",
      dependencies: [
        "PDFKitGuard", .product(name: "AccessibilityIDs", package: "Core"), .product(name: "Core", package: "Core"),
      ],
      swiftSettings: settings
    ),
    // The one PDFKit call that raises an Objective-C exception Swift can't catch (#311).
    .target(name: "PDFKitGuard"),
    .target(
      name: "PDFEngineTestSupport",
      dependencies: ["PDFEngine"],
      swiftSettings: settings
    ),
    .testTarget(
      name: "PDFEngineTests",
      dependencies: [
        "PDFEngine", "PDFEngineTestSupport", "PDFKitGuard", .product(name: "CoreTestSupport", package: "Core"),
        .product(name: "Core", package: "Core"),
      ],
      swiftSettings: settings
    ),
  ]
)
