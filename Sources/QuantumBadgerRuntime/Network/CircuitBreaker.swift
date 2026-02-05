import Foundation

actor CircuitBreaker {
    enum State {
        case closed
        case open(until: Date)
        case halfOpen
    }

    private(set) var state: State = .closed
    private var failureCount: Int = 0
    private var halfOpenInFlight: Bool = false

    let failureThreshold: Int
    let cooldownSeconds: TimeInterval

    init(failureThreshold: Int = 3, cooldownSeconds: TimeInterval = 60) {
        self.failureThreshold = max(1, failureThreshold)
        self.cooldownSeconds = max(5, cooldownSeconds)
    }

    func allowRequest() -> Bool {
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

    func recordSuccess() {
        _ = recordSuccessAndReportTransition()
    }

    func recordSuccessAndReportTransition() -> Bool {
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

    func recordFailure() -> Bool {
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

    func stateSnapshot() -> State {
        state
    }
}
