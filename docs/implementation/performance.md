# Device and field acceptance protocol

Status: not run. No device latency, energy, accuracy or event-delay result is claimed.
The package's deterministic capacity tests are correctness evidence only.

Before measurement, record the SDK commit, chosen iPhone model, iOS version,
Release toolchain/build, location-validity window, buffer, sampling configuration,
dataset hash/revision, and product latency/accuracy/power thresholds. Select a
representative site and obtain permission before recording location traces. Keep
traces local and outside version control.

## Query workload

Use both deterministic capacity fixtures: 100 separated 100-edge polygons, then
100 overlapping 100-edge polygons. Restore snapshots before timing; exclude GPS,
download, parsing and startup. Record warmup and measured sample counts. Measure
from receipt of each valid LocationSample to completion of all region evaluations.
Record P50 and P95 in milliseconds, exact expected match IDs, and event counts.
Run a separate instrumented Release pass showing no store-read counter increase
during queries; keep instrumentation out of the timing pass.

## Foreground and permission behavior

Observe expected versus actual results for not-determined, denied, restricted and
disabled services; precise/reduced accuracy; authorization revoked during tracking;
foreground/background/restart; empty dataset then enabled region; and SDK-managed
versus host-provided mode. Verify the SDK never prompts for permission and the host
stops monitoring when leaving foreground. The first confirmable sample after an
interruption must establish a baseline without a false crossing.

## Field comparison

Compare adaptive sampling with a fixed policy using the same device, OS, datasets,
routes and session duration. Include stationary boundary jitter and near/far walking
routes, valid and unknown speed, and changing horizontal accuracy. Independently
record crossing times. Record repetitions, false/missed/late events, uncertainty
frequency, delay distributions, update frequency and platform energy measurements.
Document weather/site conditions and measurement limitations.

No pass/fail verdict is possible until product thresholds are agreed and the runs
are performed. Simulator compilation and fake-provider tests do not replace these
observations.
