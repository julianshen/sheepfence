# Data/schema review

Extensive review conducted; no high-confidence issues found that meet the reporting threshold.

Models.swift:4–11 includes both dataset and feature in RegionID identity.
Models.swift:60–76 carries observation and last-confirmed state separately, with
revision and time. Models.swift:86–95 distinguishes submitted dataset metadata
from the active revision after an older-version skip.

SnapshotStore.swift:12–16 retains original bytes and a digest, but no validated
region model or Core Data schema exists yet. Storage/README.md records required
fields and transaction rules. Public metadata constructors are plain value
constructors, not import validators; do not treat their synthesized Codable
conformance as a schema-v1 validator. Timestamp-format, ID and revision validation
must be implemented at the import boundary.
