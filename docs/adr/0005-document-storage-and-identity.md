# ADR-0005: Files as the source of truth, in iCloud Drive

**Status:** accepted (2026-09-28)

**Context.** Users expect PDFs to be real files they can see in Files, share and back up. Metadata sync must not lose track of a document when it is renamed or moved.

**Decision.** Documents are files in the app's iCloud Drive ubiquity container (local container when iCloud is off). Access is coordinated (`NSFileCoordinator`, file presenters), writes are atomic, conflicts use `NSFileVersion`. The editor adopts the iOS 27 SwiftUI document protocols (`ReadableDocument`/`WritableDocument`). Open-in-place uses security-scoped bookmarks. Deleted documents stay in Recently Deleted for 30 days. Stable document identity across renames and devices is settled by a spike before implementation (readiness blocker, major).

**Alternatives considered.** An opaque database of documents (breaks Files integration). CloudKit assets (poor fit for large files). `DocumentGroup` only (no room for the library experience).

**Consequences.** Two sync channels (iCloud Drive for files, CloudKit for metadata) must agree on identity; the spike decides the mechanism. No server of ours holds user documents.

**Pillars served.** PIL-1, PIL-5, PIL-6, PIL-7

**References.** [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator) · [InfoQ: SwiftUI adds new Document protocol (WWDC26)](https://www.infoq.com/news/2026/07/swiftui-wwdc26/)
