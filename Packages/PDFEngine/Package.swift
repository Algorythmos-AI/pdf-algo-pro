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
      dependencies: [.product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
    .target(
      name: "PDFEngineTestSupport",
      dependencies: ["PDFEngine"],
      swiftSettings: settings
    ),
    .testTarget(
      name: "PDFEngineTests",
      dependencies: [
        "PDFEngine", "PDFEngineTestSupport", .product(name: "CoreTestSupport", package: "Core"),
        .product(name: "Core", package: "Core"),
      ],
      swiftSettings: settings
    ),
  ]
)
