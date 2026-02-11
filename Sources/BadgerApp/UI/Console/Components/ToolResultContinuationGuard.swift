import Foundation
import BadgerCore

actor ToolResultContinuationGuard {
    private var continuation: CheckedContinuation<ToolResult, Never>?
    private var didResume: Bool = false

    var isResolved: Bool {
        didResume
    }

    func install(_ continuation: CheckedContinuation<ToolResult, Never>) {
        if didResume {
             // Already resumed, cannot reuse.
             return
        }
        self.continuation = continuation
    }

    func resume(_ result: ToolResult) {
        guard !didResume else { return }
        didResume = true
        let cont = self.continuation
        self.continuation = nil
        cont?.resume(returning: result)
    }
}
