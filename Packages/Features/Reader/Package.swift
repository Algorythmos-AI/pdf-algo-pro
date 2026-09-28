// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
        .defaultIsolation(MainActor.self),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "Reader",
  defaultLocalization: "en",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "ReaderFeature", targets: ["ReaderFeature"]),
  ],
  dependencies: [
    .package(path: "../../Core"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../PDFEngine"),
  ],
  targets: [
    .target(
      name: "ReaderFeature",
      dependencies: [.product(name: "Core", package: "Core"), .product(name: "DesignSystem", package: "DesignSystem"), .product(name: "PDFEngine", package: "PDFEngine")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "ReaderFeatureTests",
      dependencies: ["ReaderFeature", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
