# ADR-0006: SwiftData for the rebuildable library index

**Status:** accepted (2026-09-28)

**Context.** The library needs fast queries over metadata, tags, recents and derived data (OCR text, AI caches). Because files are the source of truth, this store is an index, not the record.

**Decision.** SwiftData with a versioned schema and migration plan, behind a `LibraryStore` protocol, designed for CloudKit private-database sync (optional or defaulted attributes, no unique constraints). Fallback ladder on open: on disk, recreate after a second failure, in memory, run without the index. The index can always be rebuilt from the files.

**Alternatives considered.** Core Data (mature; more code; no advantage for a rebuildable index). GRDB/SQLite FTS5 (third-party or hand-written SQL; kept as the search fallback). JSON sidecars (slow to query at scale).

**Consequences.** A failed store never loses a document. The protocol lets a Core Data implementation replace SwiftData without touching features if scale or migration problems appear; performance tests use a 10,000-document library. Derived data (OCR text, embeddings, AI caches) stays on each device, so the store uses two configurations: user metadata synced through the CloudKit private database, and a local-only store for derived data ([privacy architecture](../privacy-architecture.md)).

**Pillars served.** PIL-1, PIL-6

**References.** [SwiftData](https://developer.apple.com/documentation/swiftdata) · [Fatbobman's Swift Weekly #139 (WWDC26 summary)](https://fatbobman.com/en/weekly/issue-139/)

**Addendum (2026-09-30).** "The index can always be rebuilt from the files" holds for the document list and
the search text, not for what people add: favourites, tags, reading positions and deletion dates exist only in
the index. The index store is therefore backed up with the app's data; only the search text, which is rebuilt
from the files, is excluded from backups. After a rebuild, files left in Recently Deleted return as deleted
documents, so they are still purged after 30 days.
