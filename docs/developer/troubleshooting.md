# Troubleshooting

Start with `await client.state()`: check the active mode, dataset readiness and location availability before interpreting region results.

## Common symptoms

| Symptom | Check / response |
|---|---|
| `storeAlreadyOpen` | Reuse the existing client. Symlink aliases still identify the same store. Pending operations can retain its lease. |
| `datasetNotReady` | Install every required dataset; inspect `state().readiness`. |
| No entry events from `evaluate` | It is pure. Use active `.hostProvided` plus `submit`, or `.sdkManaged`. |
| `monitoringNotStarted` | Start host-provided monitoring before submitting fixes. |
| `sourceModeConflict` | Stop before switching modes; do not submit host fixes in SDK-managed mode. |
| `regionNotFound` | Check both components of `RegionID`, and whether a replacement removed it. |
| `boundaryUncertain` | The reported accuracy plus buffer cannot confirm the side of the boundary. Do not coerce it to outside. |
| `.unavailable(.staleLocation)` | Supply a fresh timestamped fix; review your configured maximum age. |
| `.unavailable(.outOfOrderLocation)` | Keep host-provided samples in timestamp order. |
| No boundary distance | Inspect `.unsupported`; the geometry may exceed the local distance model. |
| `eventBufferOverflow` | Resubscribe for current state, reduce work per event, or choose an appropriate larger buffer. Missed events are not replayed. |

## Source and import errors

Handle `GeofenceError.sourceFailed` by its `SourceFailure`: `unsupportedScheme`, `httpStatus`, `timeout`, `byteLimitExceeded`, `redirectRejected`, `network` or `fileRead`. Retry transient failures according to your app's policy; do not repeatedly retry invalid geometry or an unsupported scheme. SDK source errors omit raw URLs, credentials and transport errors.

```swift
do {
    _ = try await client.installSnapshot(from: snapshotURL)
} catch GeofenceError.sourceFailed(let failure) {
    print("Snapshot source failed:", failure)
} catch GeofenceError.invalidSnapshot(let regionID, let path, let reason) {
    print("Invalid snapshot:", regionID ?? "dataset", path, reason)
} catch {
    print("Install failed:", error)
}
```

Use the path and region ID in import diagnostics to fix the producer. A same-revision conflict means different source bytes were supplied for an already committed revision. Increment the dataset revision when publishing a replacement. Preserve the last working snapshot on the server as well as in your app's rollout process.

## Permissions and missing GPS

An SDK-managed provider cannot bypass app authorization. Confirm the app's usage description, permission flow and device Location Services. A denied permission, disabled services or temporary absence of fixes is unavailable location, not an exit. Reduced accuracy is reported separately and can widen boundary uncertainty.

The SDK does not promise background operation or automatic permission requests. Synthetic test samples and benchmark success do not validate a real GPS route. Test foreground transitions, authorization changes and reduced accuracy on physical hardware for your host app.

## Reporting an issue

Include SDK commit, OS/device, mode, sanitized configuration, expected behavior and a minimal synthetic snapshot/sample if possible. Avoid sharing real movement traces or authenticated source URLs. Report through [GitHub Issues](https://github.com/julianshen/sheepfence/issues).
