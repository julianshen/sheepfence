import CoreData
import Foundation

/// A single serial queue owns the entire compare/replace/save critical section.
/// The context is never used outside that queue; only value snapshots escape.
final class CoreDataSnapshotStore: SnapshotStore, @unchecked Sendable {
    typealias CommitInterceptor = @Sendable (Int) async throws -> Void
    typealias SaveInterceptor = @Sendable (Int) throws -> Void

    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private let queue = DispatchQueue(label: "SheepFence.CoreDataSnapshotStore")
    private let beforeCommit: CommitInterceptor
    private let beforeSave: SaveInterceptor

    init(
        url: URL,
        beforeCommit: @escaping CommitInterceptor = { _ in },
        beforeSave: @escaping SaveInterceptor = { _ in }
    ) throws {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        self.container = try Self.makeContainer(with: description)
        self.context = container.newBackgroundContext()
        self.context.undoManager = nil
        self.beforeCommit = beforeCommit
        self.beforeSave = beforeSave
    }

    init(
        inMemory: Bool,
        beforeCommit: @escaping CommitInterceptor = { _ in },
        beforeSave: @escaping SaveInterceptor = { _ in }
    ) throws {
        guard inMemory else {
            throw GeofenceError.invalidConfiguration("Use init(url:) for the SQLite store")
        }
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        self.container = try Self.makeContainer(with: description)
        self.context = container.newBackgroundContext()
        self.context.undoManager = nil
        self.beforeCommit = beforeCommit
        self.beforeSave = beforeSave
    }

    func loadCommittedSnapshots() async throws -> [ValidatedSnapshot] {
        try await perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "DatasetRecord")
            request.sortDescriptors = [NSSortDescriptor(key: "datasetID", ascending: true)]
            return try context.fetch(request).map(Self.snapshot(from:))
        }
    }

    func commit(_ snapshot: ValidatedSnapshot) async throws -> SnapshotCommit {
        try await beforeCommit(snapshot.metadata.revision)
        return try await perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "DatasetRecord")
            request.predicate = NSPredicate(format: "datasetID == %@", snapshot.metadata.id)
            request.fetchLimit = 1
            let current = try context.fetch(request).first
            if let current {
                let currentSnapshot = try Self.snapshot(from: current)
                if currentSnapshot.metadata.revision > snapshot.metadata.revision {
                    return SnapshotCommit(
                        result: InstallResult(
                            dataset: snapshot.metadata,
                            activeRevision: currentSnapshot.metadata.revision,
                            outcome: .olderVersionSkipped
                        ), effectiveSnapshot: currentSnapshot
                    )
                }
                if currentSnapshot.metadata.revision == snapshot.metadata.revision {
                    guard currentSnapshot.sourceBytes != snapshot.sourceBytes else {
                        return SnapshotCommit(
                            result: InstallResult(
                                dataset: snapshot.metadata,
                                activeRevision: currentSnapshot.metadata.revision,
                                outcome: .unchanged
                            ), effectiveSnapshot: currentSnapshot
                        )
                    }
                    throw GeofenceError.revisionConflict(
                        datasetID: snapshot.metadata.id, revision: snapshot.metadata.revision
                    )
                }
            }

            do {
                if let current {
                    context.delete(current)
                }
                try Self.insert(snapshot, into: context)
                try self.beforeSave(snapshot.metadata.revision)
                try context.save()
            } catch {
                // Restore both the in-memory context and the prior durable snapshot.
                context.rollback()
                throw error
            }

            return SnapshotCommit(
                result: InstallResult(
                    dataset: snapshot.metadata,
                    activeRevision: snapshot.metadata.revision,
                    outcome: .installed
                ), effectiveSnapshot: snapshot
            )
        }
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let result: Result<T, Error> = self.context.performAndWait {
                    do { return .success(try operation(self.context)) }
                    catch { return .failure(error) }
                }
                continuation.resume(with: result)
            }
        }
    }

    private static func makeContainer(
        with description: NSPersistentStoreDescription
    ) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(
            name: "SheepFence", managedObjectModel: CoreDataModel.make()
        )
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if let loadError {
            throw GeofenceError.storageFailed(String(describing: loadError))
        }
        return container
    }

    private static func insert(_ snapshot: ValidatedSnapshot, into context: NSManagedObjectContext) throws {
        let dataset = NSEntityDescription.insertNewObject(
            forEntityName: "DatasetRecord", into: context
        )
        dataset.setValue(snapshot.metadata.id, forKey: "datasetID")
        dataset.setValue(snapshot.metadata.revision, forKey: "revision")
        dataset.setValue(snapshot.metadata.generatedAt, forKey: "generatedAt")
        dataset.setValue(snapshot.sourceBytes, forKey: "sourceBytes")
        dataset.setValue(snapshot.sha256, forKey: "sha256")

        for (index, region) in snapshot.regions.enumerated() {
            let record = NSEntityDescription.insertNewObject(
                forEntityName: "RegionRecord", into: context
            )
            record.setValue(region.id.featureID, forKey: "featureID")
            record.setValue(region.name, forKey: "name")
            record.setValue(region.enabled, forKey: "enabled")
            record.setValue(region.priority, forKey: "priority")
            record.setValue(index, forKey: "ordinal")
            record.setValue(try JSONEncoder().encode(region.geometry), forKey: "geometry")
            record.setValue(try JSONEncoder().encode(region.bounds), forKey: "bounds")
            record.setValue(dataset, forKey: "dataset")
        }
    }

    private static func snapshot(from dataset: NSManagedObject) throws -> ValidatedSnapshot {
        let id = try required(String.self, forKey: "datasetID", in: dataset)
        let revision = try required(Int.self, forKey: "revision", in: dataset)
        let generatedAt = try required(Date.self, forKey: "generatedAt", in: dataset)
        let sourceBytes = try required(Data.self, forKey: "sourceBytes", in: dataset)
        let sha256 = try required(Data.self, forKey: "sha256", in: dataset)
        let relationship = try required(NSSet.self, forKey: "regions", in: dataset)
        let records = relationship.allObjects.compactMap { $0 as? NSManagedObject }
        let regions = try records.sorted { left, right in
            (left.value(forKey: "ordinal") as? Int ?? 0) < (right.value(forKey: "ordinal") as? Int ?? 0)
        }.map(region(from:))

        return ValidatedSnapshot(
            metadata: DatasetMetadata(id: id, revision: revision, generatedAt: generatedAt),
            sourceBytes: sourceBytes, sha256: sha256, regions: regions
        )
    }

    private static func region(from record: NSManagedObject) throws -> Region {
        let dataset = try required(NSManagedObject.self, forKey: "dataset", in: record)
        let datasetID = try required(String.self, forKey: "datasetID", in: dataset)
        let featureID = try required(String.self, forKey: "featureID", in: record)
        let geometryData = try required(Data.self, forKey: "geometry", in: record)
        let boundsData = try required(Data.self, forKey: "bounds", in: record)
        do {
            return Region(
                id: RegionID(datasetID: datasetID, featureID: featureID),
                name: try required(String.self, forKey: "name", in: record),
                enabled: try required(Bool.self, forKey: "enabled", in: record),
                priority: try required(Int.self, forKey: "priority", in: record),
                geometry: try JSONDecoder().decode(RegionGeometry.self, from: geometryData),
                bounds: try JSONDecoder().decode([RegionBounds].self, from: boundsData)
            )
        } catch let error as GeofenceError {
            throw error
        } catch {
            throw GeofenceError.storageFailed("Cannot decode region \(featureID): \(error)")
        }
    }

    private static func required<T>(
        _ type: T.Type, forKey key: String, in record: NSManagedObject
    ) throws -> T {
        guard let value = record.value(forKey: key) as? T else {
            throw GeofenceError.storageFailed("Missing or invalid \(key)")
        }
        return value
    }
}
