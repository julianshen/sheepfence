# Codex implementation review — interim

Review scope: OpenCode import/geometry and pi Core Data store, before final handoff.

## Reproduced defects returned to author

- Foundation JSONSerialization numeric 1 satisfies Swift `is Bool`; type identity must distinguish CFBoolean from numbers. Confirmed with independent Swift execution. Strict schema/value tests now cover the case.
- Valid tiny noncollinear polygon (side 1e-7 degrees around 10,20) rejected by the fixed 1e-12 degree-squared collinearity threshold. Independent ReviewRegressionTests reproduced invalidSnapshot; author fix independently verified; regression now passes.
- Additional source issues returned for correction/tests: 2D coordinate arity, Boolean coordinates/numeric enabled, safe integer conversion, exact closure, closed-ring internal contract, MultiPolygon paths, strict calendar dates, periodic longitude candidates and distances, conservative projection fallback.

## Independent checks

ReviewRegressionTests initially passed 6/7; tiny polygon case failed. These are Codex-owned cases, not author-generated test oracles.

StoreTests independently passed 6/6: SQLite reopen, full region replacement/empty snapshot, exact retry/older skip/conflict, rollback, held older revision after newer commit, failed higher revision allowing lower commit. Store uses one serial queue and a private-context synchronous transaction for revision comparison, replacement and save; no Core Data objects escape as public query values.

At this intermediate stage, store and geometry approval was pending. The follow-up
checkpoint verdict below supersedes that status. Pi is blocked by its provider
balance; no provider/model configuration was modified.

## Follow-up verification

A further wide-coordinate-linear polygon counterexample (inside point 150,0.5 in a
-170..170 polygon with intermediate vertices) exposed query-relative unwrap changing
the interior. Author restored raw-coordinate containment; the new independent test
passes. All eight Codex regression tests pass. Full package: 57 tests in nine suites
passed, including production-path capacity tests. iOS 16 simulator source build passed.

Import/geometry and store are accepted for the current implementation checkpoint,
subject to documented local meter-model limits and final integration/device gates.
OpenCode's low-priority store scheduling observation does not require a change:
commit order need not equal request arrival order; the spec requires atomic revision
comparison and the highest successfully committed revision, which are tested.
OpenCode's final facade review found no blockers. Pi review of the engine/facade
remains pending. Final checkpoint verification repeated the 57-test package pass
and iOS 16 simulator source build on the corrected geometry implementation.
