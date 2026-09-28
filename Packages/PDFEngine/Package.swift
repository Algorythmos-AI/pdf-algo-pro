// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "PDFEngine",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "PDFEngine", targets: ["PDFEngine"]),
  ],
  dependencies: [
    .package(path: "../Core"),
  ],
  targets: [
    .target(
      name: "PDFEngine",
      dependencies: [.product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "PDFEngineTests",
      dependencies: ["PDFEngine", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
