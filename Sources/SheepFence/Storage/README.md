# Persistence implementation boundary

Implement `SnapshotStore` with Core Data before exposing a concrete SDK client.
The current package contains the contract only; it does not persist data yet.

The model needs Dataset (unique ID, revision, generatedAt, SHA-256, original
bytes) and Region (dataset relationship, feature ID, name, enabled, priority,
geometry, bounding rectangles). Delete regions omitted by replacement snapshots.

Validate and prepare a complete immutable snapshot before committing. Serialize
writes and recheck the effective revision inside the commit operation. Save all
changes in one Core Data transaction, then publish the prepared memory snapshot.
Rollback on errors, preserving the previous query snapshot. Exact-byte retries
at the same revision are unchanged; different bytes are revision conflicts.

Tests must cover persistent-store reopening, save failure, and concurrent imports
of revisions 4 and 5. Query evaluation must perform zero Core Data fetches.
