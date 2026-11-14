# Implementation progress

## Completed gate

- Baseline local branch: `implementation/v1`, scaffold commit `cf0d4ac`.
- Shared contracts: `c1871d1`; approved by OpenCode and pi. Six contract tests passed independently.
- Shared workspace uses disjoint file ownership; Codex alone stages/commits integration.

## Work in progress

- OpenCode: import/geometry implemented; independently reproduced numeric-type, tiny-polygon and wide-polygon defects corrected. Author suites and Codex regressions pass. Engine, observation, store and facade cross-reviews complete with no blockers.
- Pi: resumed successfully after the requested retry. Independent engine/observation/facade review found no blockers. Source/provider fixes and deterministic regression tests are complete; pi independently reran all 86 tests successfully.
- Codex: observation transitions, engine, lifecycle facade and integration/capacity tests implemented. Both peer reviews of the checkpoint are complete. Public construction and initial sampling integration added and reviewed by both peers.

## Current verification (not final acceptance)

Final current package: 86 tests in 13 suites passed independently in Codex and pi scratch builds. iOS 16 arm64 simulator source build passed without compiler warnings. OpenCode approved the source/provider/facade and acceptance oracles. No device testing performed.

- Four observation tests passed: baseline/crossing/repeat, equality uncertainty, uncertain-first, data rebase/reset.
- Six injected-engine tests passed: no-op/failure preservation, geometry rebasing, source exclusivity/stale generation, invalid/out-of-order samples, ready-empty/missing region, concurrent revisions.
- Six facade tests passed with a fake location provider: source-mode exclusivity, idempotence/callback cleanup, empty data, overlapping lifecycle calls, no-location/evaluation-failure events.
- Five production-path acceptance tests passed using the current importer, Core Data and engine: bundled sample and SQLite reopen; separated 100 x 100-edge regions; overlapping 100 regions with exactly one enter/exit per region. Store-call probe and Core Data diagnostic counter stayed unchanged during queries. Added real garden movement/jitter and hole/MultiPolygon query cases.
- Results include the final geometry corrections and wide-polygon regression. Real device behavior, Release performance and field energy/accuracy remain pending.
- Import/geometry and transactional storage checkpoint: `5490715`. Production downloader, Core Location provider, adaptive sampling and public construction are implemented and accepted for this integration checkpoint; this is not a release-ready SDK.

## External gates

Pi's earlier HTTP 402 blocker cleared on the user-requested retry using its then-selected model. No provider/model configuration was changed by Codex. Device selection, field access and measured release acceptance remain pending.

## Remaining integration and release work

See acceptance.md for exact production-versus-injected coverage. An executable iOS host, a combined real-import deletion/expansion/concurrent-failure sequence, device lifecycle observations, and agreed Release/field measurements remain pending. No release/tag/push is implied by this checkpoint.
