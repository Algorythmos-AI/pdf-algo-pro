import Core
import Testing

@Suite("Release flags and text editing access")
struct ReleaseFlagTests {
  @Test("Every release flag has an owner and a version to be removed by")
  func declared() {
    for flag in ReleaseFlag.allCases {
      #expect(!flag.owner.isEmpty)
      #expect(flag.removeBy.split(separator: ".").count == 3)
    }
  }

  /// The App Store build shows what Staging shows, except text editing until its device test is signed off.
  ///
  /// Decided in PAP-066; changing a value here is a decision, recorded in the decision register.
  @Test("The App Store build has the flags PAP-066 decided for 1.0")
  func shippedInOnePointZero() {
    let on = Set(ReleaseFlag.allCases.filter(\.compiledDefault))
    #expect(on == [.readingControls, .widerRecognition, .baseFormMatching, .documentDragging, .documentRecognition])
    #expect(!ReleaseFlag.textEditing.compiledDefault, "Text editing waits for its device test (PAP-066)")
  }

  @Test("A flag is overdue once the app's version reaches the one it must be removed by")
  func overdue() {
    let flag = ReleaseFlag.textEditing
    #expect(!flag.isOverdue(atVersion: "0.1.0"))
    #expect(!flag.isOverdue(atVersion: "1.0.9"))
    #expect(!flag.isOverdue(atVersion: "1.0"))
    #expect(flag.isOverdue(atVersion: "1.1.0"))
    #expect(flag.isOverdue(atVersion: "1.1"))
    #expect(flag.isOverdue(atVersion: "2.0.0"))
    #expect(!flag.isOverdue(atVersion: "not a version"))
  }

  @Test("A fixed access always gives its answer")
  func fixedAccess() async {
    for access in [TextEditingAccess.available, .locked, .hidden] {
      #expect(await FixedTextEditingAccess(access).textEditingAccess() == access)
    }
  }
}
