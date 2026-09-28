// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "Scan",
  defaultLocalization: "en",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "ScanFeature", targets: ["ScanFeature"])
  ],
  dependencies: [
    .package(path: "../../Core"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../PDFEngine"),
    .package(path: "../../Scanning"),
  ],
  targets: [
    .target(
      name: "ScanFeature",
      dependencies: [
        .product(name: "Core", package: "Core"), .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "PDFEngine", package: "PDFEngine"), .product(name: "Scanning", package: "Scanning"),
      ],
      resources: [.process("Resources")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "ScanFeatureTests",
      dependencies: ["ScanFeature", .product(name: "CoreTestSupport", package: "Core"), .product(name: "Core", package: "Core"), .product(name: "PDFEngine", package: "PDFEngine")],
      swiftSettings: settings
    ),
  ]
)
