# Code quality review — 2026-11-14

Scope: the complete initial scaffold, including Package.swift, all four Swift
source files, both test files, the GeoJSON fixture, README files and .gitignore.
Reviewed against geofence-sdk-spec-v0.3.md. This is not an SDK acceptance verdict.

Detected: Swift 6, Swift Package Manager, Foundation, Core Location, Swift Testing.
Core Data exists only as a planned persistence implementation.

Evaluation checklist:
- [x] Swift isolation, Sendable value types, throwing validation, public contracts.
- [x] Configuration boundaries, fixture packaging, dataset-scoped identity.
- [x] Data/schema type mapping and persistence boundary.
- [ ] Database indexes and ORM behavior: no implementation exists.
- [ ] Java/Spring, Go/Gin, Rust, Node/TS/JS, frontend frameworks, Python application code: not present.

Extensive review conducted; no high-confidence issues found that meet the reporting threshold.

Minor contract notes (not confirmed runtime defects):

- [Score: 70/100] Spec ambiguity: Sources/SheepFence/GeofenceClient.swift:21
  returns Bool, matching spec section 6 (line 102). Section 3 (line 71) says
  queries carry the revision used. Resolve this inconsistency before freezing
  the API: either exempt pure Boolean queries explicitly or add a result carrying
  membership and revision atomically. A separate revision lookup would not bind
  metadata to the same snapshot.
- [Score: 65/100] Sources/SheepFence/GeofenceClient.swift:15 isolates the entire
  protocol to MainActor, including synchronous geometry queries at lines 21–22.
  This constrains future query work to the UI actor. There is no engine or timing
  evidence yet, so this is a design concern, not a demonstrated performance bug.

Verification: macOS swift test passed all five test functions (including nine
parameterized invalid-input cases); arm64 iOS 16 simulator swift build passed.
The sandbox required workspace-local module caches and --disable-sandbox for
SwiftPM's nested sandbox. Neither verification ran a real-device acceptance test.

Additional OpenCode and pi reviews completed in the existing Herdr app workspace
tabs (t9 and t8), using herdr-core (`hc`). Both reported no actionable scaffold
defects and noted the same spec ambiguity and isolation design risk. See
[OpenCode review](opencode-review.md) and [Pi review](pi-review.md). OpenCode
performed static review; pi independently reran swift test successfully.
The earlier dispatch blocker came from consulting the legacy herdr CLI rather
than the current herdr-app/AGENTS.md and hc manual.
