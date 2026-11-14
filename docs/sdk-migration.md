# Migrating to the SDK facade

These changes intentionally refine the pre-1.0 API. Dataset schema/revision semantics
are unchanged; SDK version tags and dataset revisions remain independent.

| Earlier call | SDK call |
|---|---|
| `open(storeURL:configuration:downloadPolicy:samplingConfiguration:)` | `open(storeURL:configuration:)`; policies now live in configuration. Old overload forwards with its explicit adaptive settings and is deprecated. |
| Stateful `evaluate(location:) -> [RegionEvaluation]` | Start `.hostProvided`, then `submit(location:) -> EvaluationBatch`. Read `.results`. |
| One-shot evaluation using the old stateful method | `evaluate(location:) -> EvaluationBatch`; now pure, permitted in any mode. |
| `await events()` and `for await` | `try await events()` and `for try await`, with overflow/error handling. |
| Only baseline/transition events | Initial stateSnapshot and evaluated batches are also delivered; update exhaustive switches. |

Applications must explicitly choose between queries and monitoring input. Merely
renaming the returned array to `.results` does not preserve prior stateful behavior.

New catalog/distance/state/removal methods are described in the DocC catalog. Result
payloads have public initializers for application mocks. Do not create extra live clients
for one store path: duplicate opens now throw `storeAlreadyOpen`.

Stopping monitoring does not remove datasets or cancel subscriptions. Cancel the event
consumer when its owner is disposed. Keep one foreground owner of the client and stop
on scene inactivity. Permission prompts remain the app's responsibility.
