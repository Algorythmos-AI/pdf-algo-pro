import Commerce
import Core
import Foundation
import Testing

@testable import PDFAlgoPro

/// An entitlement that never changes.
private struct StubEntitlements: EntitlementProviding {
  let entitlement: Entitlement

  func currentEntitlement() async -> Entitlement { entitlement }

  func entitlementUpdates() -> AsyncStream<Entitlement> {
    AsyncStream { continuation in
      continuation.yield(entitlement)
      continuation.finish()
    }
  }
}

@MainActor
@Suite("Text editing access")
struct TextEditingAccessTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func access(enabled: Bool, granted: Bool, _ entitlement: Entitlement) async -> TextEditingAccess {
    let fixed = now
    return await AppTextEditingAccess(
      isEnabled: enabled, isGranted: granted, entitlements: StubEntitlements(entitlement: entitlement),
      now: { fixed }
    ).textEditingAccess()
  }

  @Test("A Release build shows nothing of text editing, whatever the person has bought")
  func releaseComposition() async {
    // What `forThisBuild` composes when the build is not internal: the flag's compiled default.
    let flag = ReleaseFlag.textEditing.compiledDefault
    #expect(!flag)
    for entitlement in [Entitlement.none, .subscribed, .trial(endsAt: now.addingTimeInterval(3600)), .inGracePeriod] {
      #expect(await access(enabled: flag, granted: false, entitlement) == .hidden)
    }
  }

  @Test("With the flag on, Pro decides: available with it, locked without, and never hidden")
  func entitlementDecides() async {
    #expect(await access(enabled: true, granted: false, .subscribed) == .available)
    #expect(await access(enabled: true, granted: false, .inGracePeriod) == .available)
    #expect(await access(enabled: true, granted: false, .trial(endsAt: now.addingTimeInterval(60))) == .available)
    #expect(await access(enabled: true, granted: false, .trial(endsAt: now.addingTimeInterval(-60))) == .locked)
    for entitlement in [Entitlement.none, .expired, .revoked, .inBillingRetry] {
      #expect(await access(enabled: true, granted: false, entitlement) == .locked)
    }
  }

  @Test("An internal build has the feature without a purchase, so testers reach it")
  func internalBuild() async {
    #expect(await access(enabled: true, granted: true, .none) == .available)
    // Tests run a Debug build, which is internal.
    #expect(AppTextEditingAccess.isInternalBuild)
    let composed = AppTextEditingAccess.forThisBuild(entitlements: StubEntitlements(entitlement: .none))
    #expect(composed.isEnabled && composed.isGranted)
    #expect(await composed.textEditingAccess() == .available)
  }

  @Test(
    "A launch argument fixes the access, so UI tests see each state",
    arguments: [("available", TextEditingAccess.available), ("locked", .locked), ("hidden", .hidden)])
  func launchArgument(value: String, expected: TextEditingAccess) async {
    let environment = LaunchEnvironment(arguments: ["-ui-testing", "-text-editing", value])
    #expect(environment.textEditing == expected)
    #expect(await AppContainer(environment: environment).textEditing.textEditingAccess() == expected)
    #expect(LaunchEnvironment(arguments: ["-text-editing"]).textEditing == nil)
    #expect(LaunchEnvironment(arguments: ["-text-editing", "other"]).textEditing == nil)
  }

  @Test("No release flag has outlived the version it must be removed by")
  func flagsAreNotOverdue() throws {
    let version = try #require(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
    for flag in ReleaseFlag.allCases {
      #expect(!flag.isOverdue(atVersion: version), "\(flag.rawValue) must be removed by \(flag.removeBy)")
    }
  }
}
