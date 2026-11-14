import Foundation

protocol URLTransport: Sendable {
    func data(from url: URL, maximumBytes: Int) async throws -> (Data, URLResponse)
}

/// Ephemeral session with no cookie/credential stores and redirect rejection.
final class EphemeralTransport: URLTransport, @unchecked Sendable {
    private let session: URLSession
    init(protocolClasses: [AnyClass]? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = protocolClasses
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config, delegate: RedirectRejectingDelegate(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func data(from url: URL, maximumBytes: Int) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data()
        data.reserveCapacity(min(maximumBytes, 65536))
        do {
            for try await byte in bytes {
                if Task.isCancelled { throw CancellationError() }
                if data.count >= maximumBytes {
                    bytes.task.cancel()
                    throw GeofenceError.downloadFailed("Download exceeded \(maximumBytes) bytes")
                }
                data.append(byte)
            }
        } catch {
            bytes.task.cancel()
            throw error
        }
        return (data, response)
    }
}

private final class RedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Location-free, strict source reader. It accepts only local file URLs and
/// HTTPS URLs, rejects redirects, carries no credentials/cookies, and enforces
/// caller-provided byte and timeout limits during receipt.
final class HTTPDownloader: Sendable {
    private let transport: any URLTransport
    private let policy: DownloadPolicy

    init(policy: DownloadPolicy, transport: any URLTransport = EphemeralTransport()) {
        self.policy = policy
        self.transport = transport
    }

    func read(from url: URL) async throws -> Data {
        try Task.checkCancellation()
        if url.isFileURL { return try readLocal(url) }
        guard url.scheme?.lowercased() == "https" else {
            throw GeofenceError.unsupportedSource(url)
        }
        return try await readHTTPS(url)
    }

    private func readLocal(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GeofenceError.downloadFailed("Local source not found: \(url)")
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw GeofenceError.downloadFailed("Cannot read local source: \(error)")
        }
        defer { try? handle.close() }
        var data = Data()
        while true {
            if Task.isCancelled { throw CancellationError() }
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 65536)
            } catch {
                throw GeofenceError.downloadFailed("Cannot read local source: \(error)")
            }
            guard let chunk, !chunk.isEmpty else { break }
            if data.count + chunk.count > policy.maximumBytes {
                throw GeofenceError.downloadFailed("Download exceeded \(policy.maximumBytes) bytes")
            }
            data.append(chunk)
        }
        return data
    }

    private func readHTTPS(_ url: URL) async throws -> Data {
        let timeoutNanos = timeoutNanoseconds(policy.timeout)
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [self] in
                let (data, response): (Data, URLResponse)
                do {
                    (data, response) = try await self.transport.data(from: url, maximumBytes: self.policy.maximumBytes)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as GeofenceError {
                    throw error
                } catch {
                    throw GeofenceError.downloadFailed("Transport error: \(error)")
                }
                guard let http = response as? HTTPURLResponse else {
                    throw GeofenceError.downloadFailed("Non-HTTP response")
                }
                guard (200...299).contains(http.statusCode) else {
                    throw GeofenceError.downloadFailed("HTTP status \(http.statusCode)")
                }
                // Reject redirects: delegate already rejects, but also check URL identity.
                if let finalURL = http.url, finalURL.absoluteString != url.absoluteString {
                    throw GeofenceError.unsupportedSource(finalURL)
                }
                return data
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanos)
                throw GeofenceError.downloadFailed("Download timed out after \(self.policy.timeout) seconds")
            }
            defer { group.cancelAll() }
            let result = try await group.next()!
            try Task.checkCancellation()
            return result
        }
    }

    private func timeoutNanoseconds(_ timeout: TimeInterval) -> UInt64 {
        let threshold = Double(UInt64.max) / 1_000_000_000.0
        if !timeout.isFinite || timeout >= threshold {
            return UInt64.max
        }
        if timeout <= 0 { return 0 }
        return UInt64(timeout * 1_000_000_000.0)
    }
}

struct HTTPSnapshotSource: SnapshotSource {
    private let downloader: HTTPDownloader

    init(policy: DownloadPolicy, downloader: HTTPDownloader? = nil, transport: (any URLTransport)? = nil) {
        self.downloader = downloader ?? HTTPDownloader(policy: policy, transport: transport ?? EphemeralTransport())
    }

    func read(from url: URL) async throws -> Data {
        try await downloader.read(from: url)
    }
}
