# System flows

The following is the intended flow from specification section 3 and
Sources/SheepFence/Storage/README.md, not an implemented or tested pipeline.

```mermaid
flowchart TD
    A[Local file or HTTPS snapshot] --> B[Parse and validate off the UI actor]
    B --> C[Prepare immutable query snapshot]
    C --> D[Serialized revision comparison]
    D --> E[One Core Data save]
    E --> F[Publish memory snapshot]
    F --> G[Dataset change and baseline reevaluation]
    B -->|Failure| H[Keep previous committed snapshot]
    E -->|Failure| H
    I[Location observation] --> J[Query memory snapshot]
    J --> K[Confirmed or uncertain observation]
```

Only the client and store signatures exist today (GeofenceClient.swift:20–24;
SnapshotStore.swift:6–7). There is no implemented control flow to prove atomicity.
