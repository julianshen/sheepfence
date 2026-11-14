import Foundation
protocol GeofenceClock: Sendable { func now() -> Date }
struct SystemGeofenceClock: GeofenceClock { func now() -> Date { Date() } }
