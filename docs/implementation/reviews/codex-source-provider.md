# Codex source/provider integration review

Status: approved for integration checkpoint after corrective work and independent review.

Initial source review found these blockers and returned fixes to pi:

- Shared URLSession carried ambient cookie/credential state, followed redirects
  before checking final URL, and buffered complete responses before enforcing size.
- An unstructured transport task did not promptly inherit caller cancellation.
  Converting a large finite timeout to UInt64 nanoseconds could trap; a clamp
  through Double(UInt64.max) also rounds out of range.
- Reduced accuracy used requested desiredAccuracy instead of accuracyAuthorization.
  Provider failures were absent, then mapped all errors to servicesDisabled.
- Sampling ignored accuracy and speed; the first correction still discarded
  accuracy. SamplingRegressionTests supplies independent uncertainty and hysteresis
  counterexamples.
- Queued delegate delivery must not read a new session's callback after restart.
- Source/provider tests lacked timeout, cancellation, redirect-before-follow,
  streaming-limit and authorization-state evidence; a smoke test asserting true
  cannot validate settings application.

OpenCode independently identified compile failures while pi was editing. Intermediate
compiles are not final verification. Pi must signal stable corrected sources before
the integrated suite and simulator build are rerun.

Codex integration adds public async SheepFenceClient.open with store restoration,
production dependencies, MainActor sampling state and a conservative initial reset
before provider start. PublicClientTests imports the public module without @testable
and covers local installation, offline SQLite restoration and host evaluation.
ClientLifecycleTests additionally checks reset occurs once per provider start and
before start. Pi reports both suites pass and no facade blockers.

Both capacity tests now compare Core Data's diagnostic counter as well as the
store-call wrapper before/after query workloads. Counter semantics currently count
store operations, including writes; unchanged counters establish no query-time
store access, not a measured query latency or field accuracy claim.

## Final verification

Codex and pi independently ran all 86 tests in 13 suites successfully. The iOS 16
arm64 simulator source build passed without compiler warnings. OpenCode approved
SourceTests 14/14, LocationProviderTests 8/8 and AcceptanceTests 5/5 and reviewed the
facade. Source transport now uses the production ephemeral session/redirect delegate
in tests. A response that never finishes is cancelled after the streaming byte cap;
cancellation waits for transport start and asserts cancellation is observed.

Final provider tests inspect real manager settings, isolate manually invoked
callbacks from OS callbacks, and inject fixed authorization state for deterministic
error mapping. Earlier failures came from mixing live authorization updates with
manual delegate tests; they are not retained as evidence of a production defect.
Callback capture preserves the facade's original session generation.

Store diagnostics count queued operations, including writes. Unchanged counters
across capacity queries establish no query-time store operations. Device/field
acceptance and remaining combined integration scenarios are documented separately.
