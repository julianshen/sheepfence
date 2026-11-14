# Monitoring & GPS

The host app owns permission prompts and foreground lifecycle. SheepFence separates location-source availability, current observations and historical confirmations.

## Pick one source

| Mode | Who delivers locations? | Your responsibility |
|---|---|---|
| `.sdkManaged` | SDK Core Location provider | Request permission in your app; start/stop with foreground lifecycle |
| `.hostProvided` | Your existing location pipeline | Submit fixes and report source availability |

Install the required datasets first. Start is idempotent for the same active mode. Stop before switching modes. `submit` requires active host-provided monitoring; SDK-managed mode rejects host input.

For SDK-managed use, add `NSLocationWhenInUseUsageDescription` to the app's Info.plist with a clear explanation. Your app must request authorization through its own Core Location integration. Starting the SDK does not display that prompt.

## Subscribe before starting

This helper returns a task that your application model should retain and cancel on disposal:

```swift
import SheepFence

@MainActor
func watch(_ client: SheepFenceClient) async throws -> Task<Void, Never> {
    let stream = try await client.events(bufferCapacity: 256)
    return Task { @MainActor in
        do {
            for try await event in stream {
                switch event {
                case .stateSnapshot(let state):
                    print("Initial state:", state)
                case .entered(let evaluation):
                    print("Entered:", evaluation.regionID)
                case .exited(let evaluation):
                    print("Exited:", evaluation.regionID)
                case .evaluated(let batch):
                    print("Current observations:", batch.results)
                default:
                    print("State or dataset change:", event)
                }
            }
        } catch {
            print("Subscription ended:", error)
        }
    }
}
```

Then, from your main-actor model:

```swift
let eventTask = try await watch(client)
try await client.startMonitoring(mode: .sdkManaged)

// In your app's foreground lifecycle handler, when leaving the foreground:
await client.stopMonitoring()

// When the subscriber's owner is disposed:
eventTask.cancel()
```

These are lifecycle fragments: do not immediately stop after starting in production. Serialize your app's lifecycle handling and retain one owner. The [foreground example](https://github.com/julianshen/sheepfence/tree/main/Examples/ForegroundHost) shows a complete host. Stopping does not remove datasets or cancel subscribers; it clears current session evaluations and reports `monitoringStopped` without synthetic exits.

## Host-provided GPS

```swift
try await client.startMonitoring(mode: .hostProvided)
let batch = try await client.submit(location: currentLocation)

// When your source cannot supply a fix:
try await client.updateAvailability(LocationAvailability(reason: .noLocation))

// When source availability returns, report it and submit a fresh fix:
try await client.updateAvailability(LocationAvailability())
let recovered = try await client.submit(location: nextLocation)
```

Map permission denial or disabled services to the corresponding `LocationUnavailableReason`. `reducedAccuracy` is a separate flag, not an automatic “outside” result. An available source does not itself supply a fresh fix.

## GPS loss and recovery

On interruption, current observations become unavailable while `lastConfirmed` preserves historical membership and timestamp. Display that as a past observation, not a present location. The first confirmed observation after recovery establishes a baseline; the SDK does not infer movement through an unobserved gap.

`state()` returns an atomic projection, including freshness. There is no promised timer event when a fix expires. Refresh state or use timestamps in the UI so a previously rendered fix does not remain “current” forever.

## Event delivery contract

Every subscriber receives an initial atomic `stateSnapshot`, then ordered events. `.evaluated` carries stateful input results; `.baseline` establishes confirmation; `.entered` and `.exited` represent confirmed transitions. `.datasetChanged` rebases changed geometry; `.datasetRemoved` reports explicit dataset removal. Neither replacement nor removal manufactures exits. `.evaluationFailed` reports provider-path evaluation errors, distinct from install errors thrown to the caller.

Buffers are independent and bounded (default 256). A slow subscriber terminates with `GeofenceError.eventBufferOverflow`; other subscribers continue. Resubscribe to recover current state and reconcile your UI. This does not replay missed crossings. Keep event processing lightweight and store any application-owned durable log separately.

## Sampling

The default fixed configuration requests 10 m desired accuracy and a 10 m distance filter. These are Core Location requests, not delivery guarantees. Adaptive sampling is opt-in through `.adaptive(SamplingPolicyConfiguration(...))`; its defaults are uncalibrated. Validate energy use and transition delay on real routes before relying on adaptive tuning. Background monitoring is not guaranteed.
