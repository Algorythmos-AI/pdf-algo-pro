// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .treatAllWarnings(as: .error),
]

let package = Package(
  name: "RemoteConfig",
  platforms: [.iOS(.v26), .macOS(.v26)],
  products: [
    .library(name: "RemoteConfig", targets: ["RemoteConfig"])
  ],
  targets: [
    .target(name: "RemoteConfig", swiftSettings: settings),
    .testTarget(name: "RemoteConfigTests", dependencies: ["RemoteConfig"], swiftSettings: settings),
  ]
)
