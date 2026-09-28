// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "Library",
  defaultLocalization: "en",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "LibraryFeature", targets: ["LibraryFeature"])
  ],
  dependencies: [
    .package(path: "../../Core"),
    .package(path: "../../DesignSystem"),
    .package(path: "../../PDFEngine"),
  ],
  targets: [
    .target(
      name: "LibraryFeature",
      dependencies: [
        .product(name: "Core", package: "Core"), .product(name: "DesignSystem", package: "DesignSystem"),
        .product(name: "PDFEngine", package: "PDFEngine"),
      ],
      resources: [.process("Resources")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "LibraryFeatureTests",
      dependencies: ["LibraryFeature", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
