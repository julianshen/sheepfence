import Foundation

enum ImportDiagnostic {
    static func invalid(path: String, regionID: String? = nil, reason: String) -> GeofenceError {
        .invalidSnapshot(regionID: regionID, path: path, reason: reason)
    }
}
