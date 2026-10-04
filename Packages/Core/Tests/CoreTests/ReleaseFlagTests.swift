import Core
import Testing

@Suite("Release flags and text editing access")
struct ReleaseFlagTests {
  @Test("Every release flag is off by default, has an owner and a version to be removed by")
  func declared() {
    for flag in ReleaseFlag.allCases {
      #expect(!flag.compiledDefault)
      #expect(!flag.owner.isEmpty)
      #expect(flag.removeBy.split(separator: ".").count == 3)
    }
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
