# Functional acceptance evidence

The tests below run against the production Swift package. The completed SDK has
139 passing tests on macOS and iOS Simulator, independent peer reviews, and a fresh
Release iPhone synthetic benchmark; see [SDK evidence](sdk-progress.md). Real GPS/field
energy and accuracy gates remain in [performance.md](performance.md).

| Spec case | Evidence | Scope |
|---|---|---|
| Bundled v3, garden and campus both inside | AcceptanceTests.bundledFixturePersistsAndRejectsInvalidReplacement | Real decoder, SQLite, memory query and reopen |
| Garden entry once while campus stays inside | AcceptanceTests.campusGardenMovementAndJitterUseProductionGeometry | Real decoder, Core Data, geometry and event stream |
| Hole interior, hole boundary, second MultiPolygon component | AcceptanceTests.holeAndSecondComponentQueryThroughStoreAndEngine | Real decoder, Core Data and geometry |
| Uncertainty preserves confirmation; initial baseline only | Above garden jitter case; ObservationTests; overlapping capacity case | Production jitter/event path plus state-unit boundary cases |
| Failed replacement preserves old data; concurrent revisions | Bundled acceptance case; StoreTests; EngineIntegrationTests | Invalid import with real store; storage rollback/concurrency; injected engine sequencing |
| Deletion, expansion and cache restoration without crossing | StoreTests.replacementRemovesOldRegionsAndAllowsEmptyDataset; EngineIntegrationTests.changedGeometryRebasesWithinDatasetEventOnly; PublicClientTests | Store replacement and injected rebase tested separately; public offline restoration tested end-to-end |
| Explicit unavailable reasons | EngineIntegrationTests.locationInvalidityAndOrderingDoNotInventCrossings; ClientLifecycleTests; LocationProviderTests | Injected time/source state and delegate failure mappings; real authorization transitions pending device run |
| 100 separated regions × 100 edges | AcceptanceTests.separatedHundredRegionsUsesOnlyMemoryForQueries | Independent center IDs, all-outside point, bbox uncertainty, no store counter increase |
| 100 overlapping regions × 100 edges | AcceptanceTests.overlappingHundredRegionsCrossExactlyOnceEach | 100 unique matches; exactly one enter and exit each; no store counter increase |
| Source policy | SourceTests | Actual production session redirect delegate; incomplete chunked response cancelled at cap; timeout; synchronized cancellation; huge timeout; local byte cap |

The acceptance mapping is deliberately explicit about injected versus production
paths. The combined real-import deletion/expansion/concurrent-download failure sequence is
covered by SDKReplacementTests (production source wrapper, decoder, SQLite and engine;
controlled failing URLTransport). The executable iOS host is built and benchmarked.
Real GPS and release acceptance are not inferred from green package tests.
