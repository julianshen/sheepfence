# Next implementation and verification work

Extensive review conducted; no high-confidence issues found that meet the reporting threshold.

These are planned tasks, not defects in the declared initialization scope:

1. Resolve the contains/revision spec inconsistency recorded in 01-code-quality.md.
2. Implement strict GeoJSON decoding and validated geometry before persistence.
3. Add containment, hole-boundary and MultiPolygon tests through production APIs.
4. Implement serialized Core Data commits and test failed saves, cache reopening,
   exact-byte retries, revision conflicts and concurrent revisions 4/5.
5. Test baseline reset, uncertainty, deletion/re-enable and one-source monitoring.
6. Add iOS build validation and macOS tests to CI when repository hosting is set up.
7. Run the two 100-region workloads and true-device Release timing from section 8.1.

Current five tests validate scaffold behavior only; they do not establish any
geometry, storage, monitoring or capacity acceptance result.
