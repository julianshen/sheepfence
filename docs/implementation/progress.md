# Implementation progress

## Completed gate

- Baseline local branch: `implementation/v1`, scaffold commit `cf0d4ac`.
- Shared contracts: `c1871d1`; approved by OpenCode and pi. Six contract tests passed independently.
- Shared workspace uses disjoint file ownership; Codex alone stages/commits integration.

## Work in progress

- OpenCode: import/geometry implemented; independently reproduced numeric-type, tiny-polygon and wide-polygon defects corrected. Author suites and Codex regressions pass. Engine, observation, store and facade cross-reviews complete with no blockers.
- Pi: Core Data model/store written; six focused store tests passed in its run. Source/provider implementation paused by provider HTTP 402 insufficient balance. No model/configuration changed.
- Codex: observation transitions, engine, lifecycle facade and integration/capacity tests implemented. OpenCode review complete; pi's independent review remains pending.

## Current verification (not final acceptance)

Full package: 57 tests in 9 suites passed. iOS 16 arm64 simulator source build passed. No device testing performed.

- Four observation tests passed: baseline/crossing/repeat, equality uncertainty, uncertain-first, data rebase/reset.
- Six injected-engine tests passed: no-op/failure preservation, geometry rebasing, source exclusivity/stale generation, invalid/out-of-order samples, ready-empty/missing region, concurrent revisions.
- Five facade tests passed with a fake location provider: source-mode exclusivity, idempotence/callback cleanup, empty data, overlapping lifecycle calls, no-location/evaluation-failure events.
- Three production-path acceptance tests passed using the current importer, Core Data and engine: bundled sample and SQLite reopen; separated 100 x 100-edge regions; overlapping 100 regions with exactly one enter/exit per region. Store-call probe stayed unchanged during queries.
- Results include the final geometry corrections and wide-polygon regression. Real device behavior, Release performance and field energy/accuracy remain pending.
- Import/geometry and transactional storage checkpoint: `5490715`. Production downloader, Core Location provider, adaptive sampling and public construction path remain unfinished; this is not a release-ready SDK.

## Pending external decision

Pi's configured provider returned HTTP 402 insufficient balance. User was asked whether to use another configured model, continue with Codex/OpenCode leaving pi reviews pending, or wait for balance restoration. No model changes or provider updates were made.
