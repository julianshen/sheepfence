import Darwin
import Foundation

/// Process-local exclusivity for one canonical store URL.
/// Facade contract: obtain the lease before create/open, retain it until the
/// engine/store tasks finish. Duplicate `open` calls with the same canonical
/// store URL throw `storeAlreadyOpen`. Cross-process locking is explicitly
/// unsupported (see sdk-contracts.md).
final class StoreLease: Sendable {
    /// Canonicalized store URL: parent symlinks are resolved even when the
    /// store file does not exist yet, so alias paths cannot open one store twice.
    let url: URL

    /// Unique per lease; a stale lease's release cannot remove a newer lease.
    /// File-private so only the registry in this file can compare tokens.
    fileprivate let token: UUID

    fileprivate init(url: URL, token: UUID) {
        self.url = url
        self.token = token
    }

    /// Acquires the process-local lease for the canonicalized store URL.
    /// Requires an absolute file URL; duplicate holders throw `storeAlreadyOpen`.
    static func acquire(for url: URL) throws -> StoreLease {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw GeofenceError.invalidConfiguration("Store URL must be an absolute file URL")
        }
        return try StoreLeaseRegistry.shared.acquire(canonicalStoreURL(for: url))
    }

    /// Idempotent. Releasing a stale lease never removes a newer lease that
    /// holds the same canonical URL.
    func release() {
        StoreLeaseRegistry.shared.release(self)
    }

    /// Deallocation releases the reservation so failed opens and cancellation
    /// never leak a lease.
    deinit { StoreLeaseRegistry.shared.release(self) }
}

private func canonicalStoreURL(for url: URL) -> URL {
    let raw = url.path
    // Resolve the longest existing prefix so parent symlinks canonicalize even
    // for brand-new store files (a fully existing path is fully resolved, and
    // a nonexistent final component is appended as given). The realpath output
    // is already absolute and symlink-free; do NOT run string standardization
    // over it afterwards - NSString.standardizingPath is filesystem-sensitive
    // on this toolchain (it rewrites an existing /private/var prefix back to
    // /var), which would drift the registry key once the store file is created.
    let components = raw.split(separator: "/").map(String.init)
    var resolvedPrefix = "/"
    var index = 0
    while index < components.count {
        let candidate = (resolvedPrefix as NSString).appendingPathComponent(components[index])
        guard let resolved = resolvedRealpath(candidate) else { break }
        resolvedPrefix = resolved
        index += 1
    }
    // Lexically normalize only the nonexistent suffix (no filesystem access).
    // Popping ".." into the resolved prefix stays filesystem-correct because
    // every prefix component is a real, already-resolved directory.
    var suffix = resolvedPrefix
    for component in components[index...] {
        switch component {
        case ".": continue
        case "..":
            if suffix != "/" { suffix = (suffix as NSString).deletingLastPathComponent }
        default:
            suffix = (suffix as NSString).appendingPathComponent(component)
        }
    }
    return URL(fileURLWithPath: suffix)
}

/// realpath with caller-managed buffer; nil when the path does not fully exist.
private func resolvedRealpath(_ path: String) -> String? {
    guard let buffer = realpath(path, nil) else { return nil }
    defer { free(buffer) }
    return String(cString: buffer)
}

/// Synchronous lock-protected registry. No actor hop: acquire/release are
/// synchronous, matching the facade's open path.
final class StoreLeaseRegistry: @unchecked Sendable {
    static let shared = StoreLeaseRegistry()

    private let lock = NSLock()
    private var holders: [String: UUID] = [:]

    private init() {}

    func acquire(_ canonical: URL) throws -> StoreLease {
        lock.lock()
        defer { lock.unlock() }
        let key = canonical.path
        if holders[key] != nil { throw GeofenceError.storeAlreadyOpen }
        let token = UUID()
        holders[key] = token
        return StoreLease(url: canonical, token: token)
    }

    func release(_ lease: StoreLease) {
        lock.lock()
        defer { lock.unlock() }
        let key = lease.url.path
        // Token equality makes release idempotent and makes a stale lease's
        // release a no-op against a newer lease for the same URL.
        if holders[key] == lease.token {
            holders.removeValue(forKey: key)
        }
    }
}
