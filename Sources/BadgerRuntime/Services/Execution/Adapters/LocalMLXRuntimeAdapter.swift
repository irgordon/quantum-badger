import Foundation
import BadgerCore

public protocol LocalMLXRuntimeAdapter: AnyObject {
    func streamResponse(for prompt: String, kind: TaskKind) -> AsyncThrowingStream<QuantumMessage, Error>
    func cancelGeneration()
}
