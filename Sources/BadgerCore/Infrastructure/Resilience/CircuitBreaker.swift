import Foundation

public actor CircuitBreaker {

    public enum State: Sendable {
        case closed
        case open(until: Date)
        case halfOpen
    }

    private(set) var state: State = .closed
    private var failureCount: Int = 0
    private var halfOpenInFlight: Bool = false

    public let failureThreshold: Int
    public let cooldownSeconds: TimeInterval
    public let identifier: String

    public init(failureThreshold: Int = 3, cooldownSeconds: TimeInterval = 60, identifier: String) {
        self.failureThreshold = max(1, failureThreshold)
        self.cooldownSeconds = max(5, cooldownSeconds)
        self.identifier = identifier
    }

    public func allowRequest() -> Bool {
        switch state {
        case .closed:
            return true
        case .open(let until):
            if Date() >= until {
                state = .halfOpen
                if halfOpenInFlight {
                    return false
                }
                halfOpenInFlight = true
                return true
            }
            return false
        case .halfOpen:
            if halfOpenInFlight {
                return false
            }
            halfOpenInFlight = true
            return true
        }
    }

    public func recordSuccess() {
        _ = recordSuccessAndReportTransition()
    }

    public func recordSuccessAndReportTransition() -> Bool {
        let wasOpen: Bool
        switch state {
        case .closed:
            wasOpen = false
        case .open, .halfOpen:
            wasOpen = true
        }
        failureCount = 0
        halfOpenInFlight = false
        state = .closed
        return wasOpen
    }

    public func recordFailure() -> Bool {
        switch state {
        case .halfOpen:
            return trip()
        case .open:
            return false
        case .closed:
            failureCount += 1
            if failureCount >= failureThreshold {
                return trip()
            }
            return false
        }
    }

    private func trip() -> Bool {
        let until = Date().addingTimeInterval(cooldownSeconds)
        state = .open(until: until)
        failureCount = 0
        halfOpenInFlight = false
        return true
    }

    public func stateSnapshot() -> State {
        state
    }
}
