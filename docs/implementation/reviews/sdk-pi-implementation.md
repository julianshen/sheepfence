# SDK P1/P2 implementation report (pi: storage, lease, source, sampling, provider)

**Status: FROZEN for OpenCode review.** No commits/pushes; no shared API/engine/facade
edits. Baseline `eb8ccd3` + approved contract (`sdk-contracts.md` v1 incl. all three
accepted pins). Pi-owned files touched: `Storage/SnapshotStore.swift`,
`Storage/CoreDataSnapshotStore.swift`, `Storage/StoreLeaseRegistry.swift` (new),
`Sources/SnapshotSource.swift`, `Sources/HTTPDownloader.swift`,
`Location/SamplingPolicy.swift`, `Tests/SheepFenceTests/StoreTests.swift`,
`SourceTests.swift`, `LocationProviderTests.swift`, `StoreLeaseTests.swift` (new),
`SamplingConfigurationTests.swift` (new).

## P1 — store removal and lease lifetime

- **`SnapshotStore.removeDataset(id:)`** is a hard protocol requirement (no default
  implementation, no fake success). `CoreDataSnapshotStore` implements it
  transactionally: fetch → snapshot region IDs → delete (cascade) → durable save
  **before** return; `context.rollback()` on failure preserves the old data; a
  missing ID is an idempotent no-op returning `wasPresent: false`. Result IDs are
  sorted datasetID-then-featureID via a shared internal `regionIDOrder` (contract
  wording; identical to `idOrder` for single-dataset removal).
- **Parent-directory creation** happens in `CoreDataSnapshotStore.init(url:)` per the
  accepted pin, so `open` only canonicalizes and leases (directory creation is
  idempotent; failure → `storageFailed`).
- **`StoreLease` / `StoreLeaseRegistry`** (`Storage/StoreLeaseRegistry.swift`):
  `final class StoreLease: Sendable`, `static acquire(for:) throws` requires an
  absolute file URL (`invalidConfiguration` otherwise) and throws
  `storeAlreadyOpen` on duplicates. Canonicalization resolves the **longest
  existing path prefix with `realpath`** and appends nonexistent suffix
  components as given — this canonicalizes parent symlinks for brand-new store
  files (verified: `NSString.resolvingSymlinksInPath` and
  `URL.standardizedFileURL` both leave them unresolved on this toolchain; macOS
  also maps `/var` → `/private/var`). Each lease carries a unique token; release
  is idempotent and a stale lease's late release cannot evict a newer lease;
  `deinit` releases so failed opens/cancellation never leak a reservation. A
  16-way concurrent acquire yields exactly one holder.
- **Interceptors**: added a removal-side `beforeRemove` hook (default no-op) to
  inject deterministic save failures in tests, mirroring the existing
  commit-side `beforeCommit`/`beforeSave` pattern.

## P2 — sources, sampling, provider

- **`DownloadPolicy.standard`** = 5,000,000 bytes / 30 s, defined in pi-owned
  `SnapshotSource.swift`; the byte cap for `installSnapshot(data:)` remains the
  engine's responsibility (Codex) per contract.
- **Source error normalization**: every transport failure now throws
  `GeofenceError.sourceFailed(SourceFailure)` directly — `unsupportedScheme`
  (non-HTTPS remote, URL never echoed), `httpStatus(Int)` (non-2xx),
  `redirectRejected` (3xx; the redirect target URL is never included, closing the
  credential-leak path the old `unsupportedSource(finalURL)` throw had),
  `timeout`, `byteLimitExceeded(maximumBytes:)` (local and streaming receipt
  paths), `network` (raw `NSError` swallowed — its description can embed request
  URLs; non-HTTP responses also map here), `fileRead` (missing and unreadable
  local files, path never echoed). `CancellationError` is preserved unchanged at
  every cancellation point. Legacy `downloadFailed`/`unsupportedSource` cases
  remain in the enum for compatibility but no new source path produces them.
- **Sampling types** (`SamplingPolicy.swift`): public
  `LocationSamplingConfiguration` (finite nonnegative `distanceFilterMeters`
  where 0 = no filter; finite strictly positive `desiredAccuracyMeters`;
  Core Location sentinel accuracies intentionally not representable — documented)
  with `.standard` 10 m/10 m and an internal `settings()` mapping;
  public `SamplingMode` `.fixed`/`.adaptive`. `SamplingPolicy` and
  `SamplingSettings` remain internal; facade closure selection is Codex's.
- **Provider**: `LocationProvider.swift` untouched (Codex-owned). Added
  authorization-mapping tests with injected `CLLocationManager` subclasses
  (notDetermined/restricted/denied → explicit reasons; allowed → reason nil;
  never dependent on the live Mac authorization state).

## Test evidence (scratch path `.build/sdk-pi`)

```text
swift test --scratch-path .build/sdk-pi --filter 'StoreTests|StoreLeaseTests'
  → 20 tests in 2 suites passed
swift test --scratch-path .build/sdk-pi --filter 'SourceTests|SamplingConfigurationTests|LocationProviderTests'
  → 33 tests in 3 suites passed
```

Full-suite run at freeze time: 133 tests / 23 suites, **4 failures — all in
Codex-owned files** (`EngineIntegrationTests` ×2, `ClientLifecycleTests`,
`AcceptanceTests`, all event-count semantics), consistent with the in-flight
engine changes and the phase-3 API switch Codex deferred until this gate.
None touch store/source/sampling/lease behavior; my components are green.
Also verified independently: OpenCode's P1 review of my storage component
(22/22) passed and is approved.

## Assumptions / notes for integration

- Removal of the last dataset leaves the store valid and reopenable; removal +
  later commit may legitimately recreate a dataset (removal is not cancellation
  of a pending install) — store-level test pins both.
- The lease registry is process-local only; cross-process locking is explicitly
  unsupported (contract).
- Fixed sampling needs no per-sample nearest-boundary engine round trip; Codex
  may skip that call for `.fixed` mode.
- Canonicalization never lexically standardizes before resolving existing
  symlinks; lexical cleanup applies only to the nonexistent suffix.
