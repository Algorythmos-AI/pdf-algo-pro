// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .treatAllWarnings(as: .error),
]

let package = Package(
  name: "Commerce",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "Commerce", targets: ["Commerce"]),
    .library(name: "CommerceTestSupport", targets: ["CommerceTestSupport"]),
  ],
  targets: [
    .target(name: "Commerce", swiftSettings: settings),
    .target(name: "CommerceTestSupport", dependencies: ["Commerce"], swiftSettings: settings),
    .testTarget(
      name: "CommerceTests", dependencies: ["Commerce", "CommerceTestSupport"], swiftSettings: settings),
  ]
)
