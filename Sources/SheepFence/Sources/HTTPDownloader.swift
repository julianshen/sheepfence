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
                    throw GeofenceError.sourceFailed(.byteLimitExceeded(maximumBytes: maximumBytes))
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
            // The rejected scheme is never echoed back: source errors must not
            // carry URLs (credentials could ride in the URL).
            throw GeofenceError.sourceFailed(.unsupportedScheme)
        }
        return try await readHTTPS(url)
    }

    private func readLocal(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GeofenceError.sourceFailed(.fileRead)
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw GeofenceError.sourceFailed(.fileRead)
        }
        defer { try? handle.close() }
        var data = Data()
        while true {
            if Task.isCancelled { throw CancellationError() }
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 65536)
            } catch {
                throw GeofenceError.sourceFailed(.fileRead)
            }
            guard let chunk, !chunk.isEmpty else { break }
            if data.count + chunk.count > policy.maximumBytes {
                throw GeofenceError.sourceFailed(.byteLimitExceeded(maximumBytes: policy.maximumBytes))
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
                    // Never surface the raw NSError: its description can embed
                    // request URLs. Structured .network carries no details.
                    throw GeofenceError.sourceFailed(.network)
                }
                guard let http = response as? HTTPURLResponse else {
                    throw GeofenceError.sourceFailed(.network)
                }
                guard (200...299).contains(http.statusCode) else {
                    if (300...399).contains(http.statusCode) {
                        // Redirects are rejected, never followed. The response's
                        // status alone is reported; no redirect target URL leaks.
                        throw GeofenceError.sourceFailed(.redirectRejected)
                    }
                    throw GeofenceError.sourceFailed(.httpStatus(http.statusCode))
                }
                return data
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanos)
                throw GeofenceError.sourceFailed(.timeout)
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
