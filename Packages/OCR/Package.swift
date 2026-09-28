// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "OCR",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "OCR", targets: ["OCR"]),
  ],
  dependencies: [
    .package(path: "../Core"),
  ],
  targets: [
    .target(
      name: "OCR",
      dependencies: [.product(name: "Core", package: "Core")],
      swiftSettings: settings
    ),
    .testTarget(
      name: "OCRTests",
      dependencies: ["OCR", .product(name: "CoreTestSupport", package: "Core")],
      swiftSettings: settings
    ),
  ]
)
