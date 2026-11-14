import Testing
@testable import SheepFence
struct CommitGateTests {
    @Test func cancellationBeforeCommitPreventsIt() {
        let gate = CommitGate()
        gate.cancel()
        #expect(throws: CancellationError.self) { try gate.begin() }
    }
    @Test func cancellationAfterCommitBeginsCannotCancelOutcome() throws {
        let gate = CommitGate()
        try gate.begin()
        gate.cancel()
        try gate.begin()
    }
}
