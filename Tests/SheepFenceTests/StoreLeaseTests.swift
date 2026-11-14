import Foundation
import Testing
@testable import SheepFence

@Suite struct StoreLeaseTests {
    private func freshStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("store.sqlite")
    }

    @Test func duplicateOpenThrowsAndReleaseRestoresAvailability() throws {
        let url = freshStoreURL()
        let first = try StoreLease.acquire(for: url)
        // Canonicalization may resolve root-level symlinks (macOS maps /var to
        // /private/var), so the canonical URL conflicts with itself and with
        // the original alias path regardless of spelling.
        #expect(first.url.isFileURL)
        #expect(throws: GeofenceError.storeAlreadyOpen) { _ = try StoreLease.acquire(for: url) }
        #expect(throws: GeofenceError.storeAlreadyOpen) { _ = try StoreLease.acquire(for: first.url) }

        first.release()
        let second = try StoreLease.acquire(for: url)
        #expect(second.url == first.url)
        second.release()
    }

    @Test func releaseIsIdempotent() throws {
        let url = freshStoreURL()
        let lease = try StoreLease.acquire(for: url)
        lease.release()
        lease.release()
        // Double release must not wedge the registry: a new lease can still be acquired.
        _ = try StoreLease.acquire(for: url)
    }

    @Test func staleReleaseCannotRemoveNewerLease() throws {
        let url = freshStoreURL()
        let stale = try StoreLease.acquire(for: url)
        stale.release()
        let current = try StoreLease.acquire(for: url)

        // The stale lease's late release must not evict the current holder.
        stale.release()
        #expect(throws: GeofenceError.storeAlreadyOpen) { _ = try StoreLease.acquire(for: url) }

        current.release()
        _ = try StoreLease.acquire(for: url)
    }

    @Test func deallocationReleasesReservation() throws {
        let url = freshStoreURL()
        var lease: StoreLease? = try StoreLease.acquire(for: url)
        #expect(lease != nil)
        #expect(throws: GeofenceError.storeAlreadyOpen) { _ = try StoreLease.acquire(for: url) }
        lease = nil
        _ = try StoreLease.acquire(for: url)
    }

    @Test func aliasPathsCannotOpenSameStoreTwice() throws {
        // Real directory plus a symlink pointing at it; the store file does not exist yet.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let real = base.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let alias = base.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: base) }

        let viaAlias = alias.appendingPathComponent("store.sqlite")
        let viaReal = real.appendingPathComponent("store.sqlite")

        // Canonical equality: the alias path and the real path are the same store.
        let viaRealLease = try StoreLease.acquire(for: viaReal)
        #expect(throws: GeofenceError.storeAlreadyOpen) { _ = try StoreLease.acquire(for: viaAlias) }
        viaRealLease.release()

        // Parent symlink canonicalized for the nonexistent store file: the lease
        // URL resolves into the real directory, never through the alias.
        let lease = try StoreLease.acquire(for: viaAlias)
        #expect(lease.url.path.hasSuffix("/real/store.sqlite"))
        #expect(throws: GeofenceError.storeAlreadyOpen) { _ = try StoreLease.acquire(for: viaReal) }
        lease.release()
        _ = try StoreLease.acquire(for: viaReal)
    }

    @Test func redundantPathComponentsCanonicalize() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let plain = base.appendingPathComponent("store.sqlite")
        let redundant = base
            .appendingPathComponent(".", isDirectory: true)
            .appendingPathComponent("store.sqlite")

        let lease = try StoreLease.acquire(for: redundant)
        #expect(throws: GeofenceError.storeAlreadyOpen) { _ = try StoreLease.acquire(for: plain) }
        lease.release()
    }

    @Test func nonFileURLsAreRejected() throws {
        #expect(throws: GeofenceError.self) { _ = try StoreLease.acquire(for: URL(string: "https://example.com/store.sqlite")!) }
        // A scheme-less URL is not a file URL; Foundation cannot reliably express
        // a relative file reference for the absolute-path guard, so only the
        // isFileURL rejection is asserted deterministically here.
        #expect(throws: GeofenceError.self) { _ = try StoreLease.acquire(for: URL(string: "relative/store.sqlite")!) }
    }

    @Test func canonicalKeyIsStableAcrossParentAndFileCreation() throws {
        // Regression for the integration blocker: the first open canonicalizes a
        // path whose parents and store file do not exist yet; creating them must
        // NOT drift the registry key, or a second open would succeed.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = base.appendingPathComponent("new/SDK.sqlite")
        defer { try? FileManager.default.removeItem(at: base) }

        let lease = try StoreLease.acquire(for: url)  // parents and file missing

        // Window 1: parent directories created, store file still missing.
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(throws: GeofenceError.storeAlreadyOpen) { _ = try StoreLease.acquire(for: url) }

        // Window 2: store file created (fully existing path now).
        try Data("store".utf8).write(to: url)
        #expect(throws: GeofenceError.storeAlreadyOpen) { _ = try StoreLease.acquire(for: url) }
        #expect(throws: GeofenceError.storeAlreadyOpen) { _ = try StoreLease.acquire(for: lease.url) }

        // Canonical spelling is identical before and after creation.
        lease.release()
        let reacquired = try StoreLease.acquire(for: url)
        #expect(reacquired.url == lease.url)
        reacquired.release()
    }

    @Test func concurrentAcquireProducesExactlyOneHolder() async throws {
        let url = freshStoreURL()
        // Successful leases must be retained until every contender finishes:
        // discarding one would let its deinit release the reservation mid-race
        // and let more than one contender legitimately acquire.
        var holders: [StoreLease] = []
        var duplicateFailures = 0
        await withTaskGroup(of: StoreLease?.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    do { return try StoreLease.acquire(for: url) }
                    catch { return nil }
                }
            }
            for await result in group {
                if let lease = result { holders.append(lease) } else { duplicateFailures += 1 }
            }
        }
        #expect(holders.count == 1)
        #expect(duplicateFailures == 15)
        holders.first?.release()
        _ = try StoreLease.acquire(for: url)
    }
}
