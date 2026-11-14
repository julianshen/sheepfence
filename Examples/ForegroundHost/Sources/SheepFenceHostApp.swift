import CoreLocation
import Foundation
import SheepFence
import SwiftUI

@main struct SheepFenceHostApp: App {
    @StateObject private var model = HostModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("100-area benchmark") {
                        Text("100 polygons × 100 edges. Synthetic locations; no GPS permission needed. 200 warmup + 2,000 measured queries per layout.")
                        Button("Run benchmark") { Task { await model.benchmark() } }
                            .disabled(model.busy)
                        if model.busy { ProgressView() }
                        Text(model.status)
                    }
                    Section("Foreground location check") {
                        Text("The bundled campus is fictional. This checks permission and lifecycle behavior, not a local crossing route. Coordinates are not recorded.")
                        Button("Request location permission") { model.requestPermission() }
                        Button("Start SDK location") { Task { await model.start() } }.disabled(model.busy)
                        Button("Stop location") { Task { await model.stop() } }
                        Text(model.locationStatus)
                    }
                    if !model.report.isEmpty {
                        Section("Results") {
                            Text(model.report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            ShareLink("Share results", item: model.report)
                        }
                    }
                }.navigationTitle("SheepFence Lab")
            }.onChange(of: phase) { phase in
                if phase != .active { Task { await model.stop() } }
                else { Task { await model.runRequestedBenchmark() } }
            }
            .task { await model.runRequestedBenchmark() }
        }
    }
}

@MainActor final class HostModel: ObservableObject {
    @Published var busy = false
    @Published var status = "Ready"
    @Published var locationStatus = "Stopped"
    @Published var report = ""
    private let permissions = CLLocationManager()
    private var client: SheepFenceClient?
    private var events: Task<Void, Never>?
    private var generation = 0
    private var ranRequestedBenchmark = false

    func runRequestedBenchmark() async {
        guard ProcessInfo.processInfo.arguments.contains("--benchmark"),
              UIApplication.shared.applicationState == .active,
              !ranRequestedBenchmark else { return }
        ranRequestedBenchmark = true
        await benchmark()
        let output = status + "\n" + report
        print(output)
        do {
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            try output.write(to: directory.appendingPathComponent("benchmark-result.txt"),
                             atomically: true, encoding: .utf8)
        } catch { print("Could not save benchmark report: \(error)") }
    }

    func requestPermission() { permissions.requestWhenInUseAuthorization() }

    private func open(name: String) async throws -> SheepFenceClient {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        return try await SheepFenceClient.open(storeURL: directory.appendingPathComponent(name + ".sqlite"),
            configuration: GeofenceConfiguration(maximumLocationAge: 86_400),
            downloadPolicy: DownloadPolicy(maximumBytes: 5_000_000, timeout: 30),
            samplingConfiguration: SamplingPolicyConfiguration())
    }

    func start() async {
        do {
            await stop()
            let epoch = generation
            let active = try await open(name: "foreground")
            guard let fixture = Bundle.main.url(forResource: "campus-v3", withExtension: "geojson") else {
                throw CocoaError(.fileNoSuchFile)
            }
            _ = try await active.installSnapshot(from: fixture)
            guard generation == epoch, UIApplication.shared.applicationState == .active else { return }
            client = active
            let stream = await active.events()
            events = Task { [weak self] in
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .locationAvailabilityChanged(let value):
                        self?.locationStatus = "Availability: \(String(describing: value.reason)); reduced accuracy: \(value.reducedAccuracy)"
                    case .evaluationFailed(let error): self?.locationStatus = "Evaluation failed: \(error)"
                    default: self?.locationStatus = "Received region event (coordinates not recorded)"
                    }
                }
            }
            try await active.startMonitoring(mode: .sdkManaged)
        } catch { locationStatus = "Error: \(error)" }
    }

    func stop() async {
        generation += 1
        await client?.stopMonitoring()
        events?.cancel(); events = nil; client = nil
        locationStatus = "Stopped"
    }

    func benchmark() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await stop()
        report = "Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)\nRelease host; public API timings, no GPS.\n"
        do {
            for overlapping in [false, true] {
                let name = overlapping ? "overlapping" : "separated"
                status = "Benchmarking \(name)…"
                let active = try await open(name: "benchmark-" + name)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".geojson")
                try CapacityFixtureFactory.make(overlapping: overlapping).write(to: url)
                _ = try await active.installSnapshot(from: url)
                let clock = ContinuousClock()
                let base = Date().addingTimeInterval(-3600)
                var times: [Double] = []
                for index in 0..<2200 {
                    guard UIApplication.shared.applicationState == .active else { throw BenchmarkError.leftForeground }
                    let region = index % 100
                    let sample = LocationSample(coordinate: Coordinate(
                        longitude: overlapping ? 10 : 10 + Double(region) * 0.05, latitude: 20),
                        timestamp: base.addingTimeInterval(Double(index) * 0.01), horizontalAccuracy: 1)
                    let start = clock.now
                    let result = try await active.evaluate(location: sample)
                    let elapsed = start.duration(to: clock.now).components
                    if index >= 200 { times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15) }
                    let ids = Set(result.filter { $0.observation == .confirmed(.inside) }.map(\.regionID.featureID))
                    let expected: Set<String> = overlapping ? Set((0..<100).map { String(format: "region-%03d", $0) }) : [String(format: "region-%03d", region)]
                    guard result.count == 100, ids == expected else { throw BenchmarkError.incorrectMatches }
                }
                times.sort()
                report += String(format: "%@: 2000 queries, P50 %.6f ms, P95 %.6f ms, P99 %.6f ms\n", name, times[999], times[1899], times[1979])
                await active.stopMonitoring()
            }
            report += "All expected region IDs verified. Includes public facade/actor dispatch. Excludes import and verification.\n"
            status = "Benchmark complete"
        } catch { status = "Failed: \(error)" }
    }
    enum BenchmarkError: Error { case incorrectMatches, leftForeground }
}
