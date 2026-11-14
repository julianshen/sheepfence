import Foundation
import Testing
@testable import SheepFence

@Suite struct SourceTests {
    final class FakeTransport: URLTransport, @unchecked Sendable {
        var data: Data
        var response: URLResponse
        var error: Error?
        var delayNanos: UInt64 = 0
        let started = AsyncStream<Bool>.makeStream()
        let cancelled = AsyncStream<Bool>.makeStream()
        init(data: Data = Data(), response: URLResponse = HTTPURLResponse(url: URL(string: "https://example.com/data")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, error: Error? = nil) {
            self.data = data; self.response = response; self.error = error
        }
        func data(from url: URL, maximumBytes: Int) async throws -> (Data, URLResponse) {
            started.continuation.yield(true)
            if delayNanos > 0 {
                do { try await Task.sleep(nanoseconds: delayNanos) }
                catch is CancellationError {
                    cancelled.continuation.yield(true)
                    throw CancellationError()
                }
            }
            if Task.isCancelled { throw CancellationError() }
            if let error { throw error }
            if data.count > maximumBytes {
                throw GeofenceError.downloadFailed("Download exceeded \(maximumBytes) bytes")
            }
            return (data, response)
        }
    }

    @Test func localReadReturnsExactBytes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".geojson")
        let bytes = Data("payload".utf8)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10))
        #expect(try await source.read(from: url) == bytes)
    }

    @Test func missingLocalReadFails() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".geojson")
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10))
        await #expect(throws: GeofenceError.self) { try await source.read(from: url) }
    }

    @Test func localReadEnforcesByteCap() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".geojson")
        let bytes = Data(repeating: 0x41, count: 20)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 5, timeout: 10))
        await #expect(throws: GeofenceError.sourceFailed(.byteLimitExceeded(maximumBytes: 5))) { try await source.read(from: url) }
    }

    @Test func missingLocalReadMapsToFileReadWithoutPathLeak() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".geojson")
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10))
        await #expect(throws: GeofenceError.sourceFailed(.fileRead)) { try await source.read(from: url) }
        // The raw failure must not carry the path: assert against the structured case.
    }

    @Test func unreadableLocalReadMapsToFileRead() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".geojson")
        try Data("payload".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10))
        await #expect(throws: GeofenceError.sourceFailed(.fileRead)) { try await source.read(from: url) }
    }

    @Test func unsupportedSchemeFailsWithoutURL() async throws {
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10))
        let url = URL(string: "http://example.com/user:secret@x")!
        await #expect(throws: GeofenceError.sourceFailed(.unsupportedScheme)) { _ = try await source.read(from: url) }
    }

    @Test func successfulHTTPSReturnsExactBytes() async throws {
        let url = URL(string: "https://example.com/data")!
        let bytes = Data("payload".utf8)
        let transport = FakeTransport(data: bytes)
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10), transport: transport)
        #expect(try await source.read(from: url) == bytes)
    }

    @Test func non2xxMapsToHttpStatus() async throws {
        let url = URL(string: "https://example.com/data")!
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10), transport: FakeTransport(data: Data(), response: response))
        await #expect(throws: GeofenceError.sourceFailed(.httpStatus(404))) { _ = try await source.read(from: url) }
    }

    @Test func redirectResponseMapsToRedirectRejectedWithoutURL() async throws {
        let url = URL(string: "https://example.com/data")!
        let final = URL(string: "https://other.example.com/data?token=secret")!
        let response = HTTPURLResponse(url: final, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10), transport: FakeTransport(data: Data("x".utf8), response: response))
        // Even when a hostile server answers 302 with credentials in the target,
        // the structured failure carries no URL at all.
        await #expect(throws: GeofenceError.sourceFailed(.redirectRejected)) { _ = try await source.read(from: url) }
    }

    @Test func nonHTTPResponseMapsToNetwork() async throws {
        let url = URL(string: "https://example.com/data")!
        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10), transport: FakeTransport(data: Data("x".utf8), response: response))
        await #expect(throws: GeofenceError.sourceFailed(.network)) { _ = try await source.read(from: url) }
    }

    @Test func oversizeContentFails() async throws {
        let url = URL(string: "https://example.com/data")!
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 3, timeout: 10), transport: FakeTransport(data: Data("payload".utf8)))
        await #expect(throws: GeofenceError.self) { _ = try await source.read(from: url) }
    }

    @Test func transportErrorMapsToNetworkWithoutRawNSError() async throws {
        let url = URL(string: "https://example.com/data")!
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10), transport: FakeTransport(error: URLError(.notConnectedToInternet)))
        await #expect(throws: GeofenceError.sourceFailed(.network)) { _ = try await source.read(from: url) }
    }

    @Test func deterministicTimeoutThrows() async throws {
        let url = URL(string: "https://example.com/data")!
        let transport = FakeTransport(data: Data("x".utf8))
        transport.delayNanos = 5_000_000_000 // 5 seconds
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 0.1), transport: transport)
        await #expect(throws: GeofenceError.sourceFailed(.timeout)) { _ = try await source.read(from: url) }
    }

    @Test func hugeTimeoutDoesNotTrap() async throws {
        let url = URL(string: "https://example.com/data")!
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 1e15), transport: FakeTransport(data: Data("x".utf8)))
        #expect(try await source.read(from: url) == Data("x".utf8))
    }

    @Test func cancellationPropagates() async throws {
        let url = URL(string: "https://example.com/data")!
        let transport = FakeTransport(data: Data("x".utf8))
        transport.delayNanos = 5_000_000_000
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 60), transport: transport)
        let task = Task { try await source.read(from: url) }
        var started = transport.started.stream.makeAsyncIterator()
        #expect(await started.next() == true)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        var cancelled = transport.cancelled.stream.makeAsyncIterator()
        #expect(await cancelled.next() == true)
    }

    // URLProtocol-based test for redirect rejection before follow.
    final class RedirectProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var destinationRequestCount = 0
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if let url = request.url, url.absoluteString.contains("redirect") {
                let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://example.com/final"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://example.com/final")!), redirectResponse: response)
                client?.urlProtocolDidFinishLoading(self)
            } else {
                RedirectProtocol.destinationRequestCount += 1
                let data = Data("ok".utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        override func stopLoading() {}
    }

    @Test func urlProtocolRedirectRejectedBeforeFollow() async throws {
        RedirectProtocol.destinationRequestCount = 0
        let transport = EphemeralTransport(protocolClasses: [RedirectProtocol.self])
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 100, timeout: 10), transport: transport)
        let url = URL(string: "https://example.com/redirect")!
        await #expect(throws: GeofenceError.self) { _ = try await source.read(from: url) }
        #expect(RedirectProtocol.destinationRequestCount == 0)
    }

    final class ChunkedProtocol: URLProtocol, @unchecked Sendable {
        static let stopped = AsyncStream<Bool>.makeStream()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(repeating: 97, count: 65_536))
            client?.urlProtocol(self, didLoad: Data(repeating: 98, count: 65_536))
            // Deliberately never finish: the size cap must abort during receipt.
        }
        override func stopLoading() { Self.stopped.continuation.yield(true) }
    }

    @Test func streamingLimitCancelsUnfinishedResponse() async throws {
        let source = HTTPSnapshotSource(policy: try DownloadPolicy(maximumBytes: 3, timeout: 2),
            transport: EphemeralTransport(protocolClasses: [ChunkedProtocol.self]))
        await #expect(throws: GeofenceError.sourceFailed(.byteLimitExceeded(maximumBytes: 3))) {
            try await source.read(from: URL(string: "https://example.com/chunks")!)
        }
        var iterator = ChunkedProtocol.stopped.stream.makeAsyncIterator()
        #expect(await iterator.next() == true)
    }
}

