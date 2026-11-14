# Pi contract-gate review

**Verdict: Approved.** No contract blocker remains for Tasks 3/6/7.

Reviewed `docs/implementation/decisions.md`, the revised public/internal Swift contracts, `Engine/MonitoringSession.swift`, `ContractTests.swift`, and the prepared-snapshot builder against approved plan revision 3. Reviewed content: HEAD `cf0d4acd6360b9d1ebb656d49799204b3ef53ad7` plus reviewed-file bundle SHA-256 `a18f664996a46119a380492d9854032a48264a8de0cdf65f6376388930d76977`.

## Store/source/provider and concurrency

- **Store:** `SnapshotStore` exchanges only Sendable value snapshots; `SnapshotCommit` returns both the install result and actual effective snapshot, supporting no-op handling and ordered engine publication without exposing managed objects. Complete compare/save serialization, rollback, reopen durability, and concurrent revision tests remain Task 3 implementation gates rather than properties proved by this declaration.
- **Source:** Async `SnapshotSource.read` is sufficient for Task 6's local/HTTPS implementations; concrete `DownloadPolicy` injection preserves explicit limits. Exact-byte receipt, redirect/credential rules, cancellation, chunk limits, and failure atomicity remain Task 6 tests.
- **Provider/client:** `@MainActor` provider callbacks and synchronous start/stop/settings are compatible with a MainActor facade delegating to the async Sendable client/engine. `MonitoringSession` gives reusable exclusive/idempotent mode transitions and generation changes; stopped-session callback rejection and provider lifecycle behavior remain Task 7 gates.

## Gate coverage correction — resolved

`ContractTests` now exercises real `MonitoringSession` idempotence/exclusivity and stop/restart behavior, `DatasetReadiness` empty-versus-missing policy, and reduced accuracy distinct from unavailability. The generic client-surface function type-checks `contains`, `query`, mode start, host availability update, and stop; revision-bearing query and download-limit contracts also have tests.

Verification executed with an isolated scratch path:

```text
swift test --scratch-path .build/pi --filter ContractTests
Build complete! (1.11s)
Test run with 6 tests in 1 suite passed after 0.001 seconds.
Exit status: 0
```

Approval covers the contract gate only, not the pending concrete store/source/provider implementations or their acceptance tests.
