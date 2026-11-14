# Pi implementation-plan review — revision 3

Reviewed the whole final revision 3 plan against spec v0.3 and the current scaffold. Review only; no implementation or plan edits.

## Prior blockers — resolved

1. **No-op install engine/event behavior — resolved.** Task 5 now explicitly requires `unchanged`, `olderVersionSkipped`, conflicts, and failed installs to preserve active geometry, observation state, last-confirmed time, and event silence. Engine tests start from confirmed `inside`, exercise identical/older/conflicting submissions, and assert the same snapshot and confirmation with no data-change, baseline, or crossing event. Genuine updates remain covered by the existing ordered-publication and reordered-completion tests.

2. **Representative field accuracy/power evidence — resolved.** Task 9 now defines a representative-site protocol covering boundary jitter, near/far routes, independently recorded crossing times, varied accuracy, valid/unknown speed, uncertainty, crossing correctness and delay distributions, update frequency, and platform-profiled energy impact. The adaptive-versus-fixed baseline, matched test conditions, privacy constraints, evidence ownership, and peer responsibilities are explicit. The field gate requires product-agreed accuracy/delay/power thresholds and remains explicitly pending without representative site/device access.

## Final assessment

No new blocker found. Feasibility and wave ordering remain coherent: shared contracts and prepared-snapshot utilities precede parallel work; store, import/geometry, observation, source, provider, and integration ownership do not conflict; Codex controls shared contracts and integration. Independent correctness and quality/concurrency review, exact counterexample reruns, and final cross-review remain mandatory.

The plan covers persistence rollback and reopen durability, serialized revision checks, ordered concurrent commits, immutable query snapshots, uncertainty-expanded candidates, dataset-contained reevaluation, source-mode and availability lifecycle behavior, all §8 functional cases, §8.1 capacity/zero-fetch requirements, Release query timing, and representative field validation. Approval applies to the implementation plan, not to implementation or device acceptance, which remain unexecuted.

**Verdict: Approved — revision 3 resolves both prior blockers and is ready for authorized implementation.**
