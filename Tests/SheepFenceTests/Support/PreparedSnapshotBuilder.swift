import Foundation
import CryptoKit
@testable import SheepFence

enum PreparedSnapshotBuilder {
    static func make(id: String = "test", revision: Int = 1, regions: [Region] = [], bytes: Data? = nil) -> ValidatedSnapshot {
        let data = bytes ?? Data("\(id)-\(revision)".utf8)
        return ValidatedSnapshot(metadata: DatasetMetadata(id: id, revision: revision, generatedAt: Date(timeIntervalSince1970: 0)),
                                 sourceBytes: data, sha256: Data(SHA256.hash(data: data)), regions: regions)
    }
}
