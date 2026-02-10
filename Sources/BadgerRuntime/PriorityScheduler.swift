import Foundation

/// Deterministic Preemptive Priority Scheduler (PPS).
///
/// Maintains a three‑tier priority queue where **Tier 0 (critical)** events
/// immediately preempt any in‑flight inference. Tasks within the same tier
/// are ordered FIFO by submission time.
///
/// The scheduler is actor‑isolated to guarantee thread‑safe queue mutation.
public actor PriorityScheduler {

    // MARK: - State

    /// Pending tasks grouped by tier.
    private var queues: [PriorityTier: [SchedulerTask]] = [
        .critical: [],
        .userInitiated: [],
        .background: [],
    ]

    /// A continuation that is fulfilled whenever a critical task is enqueued,
    /// allowing the execution manager to preempt immediately.
    private var preemptionContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Enqueue

    /// Submit a task to the scheduler.
    ///
    /// If the task is ``PriorityTier/critical``, any registered
    /// preemption waiter is immediately resumed.
    public func enqueue(_ task: SchedulerTask) {
        queues[task.tier, default: []].append(task)

        if task.tier == .critical {
            preemptionContinuation?.resume()
            preemptionContinuation = nil
        }
    }

    // MARK: - Dequeue

    /// Dequeue the highest‑priority task. Returns `nil` if empty.
    ///
    /// Evaluation order: critical → userInitiated → background.
    /// Within a tier, FIFO order is respected.
    public func dequeue() -> SchedulerTask? {
        for tier in [PriorityTier.critical, .userInitiated, .background] {
            if var queue = queues[tier], !queue.isEmpty {
                let task = queue.removeFirst()
                queues[tier] = queue
                return task
            }
        }
        return nil
    }

    // MARK: - Preemption

    /// Wait until a critical task is enqueued.
    ///
    /// The execution manager calls this concurrently with inference
    /// to implement immediate Tier 0 preemption.
    public func waitForPreemption() async {
        // If critical tasks are already queued, return immediately.
        if let q = queues[.critical], !q.isEmpty { return }

        await withCheckedContinuation { continuation in
            preemptionContinuation = continuation
        }
    }

    // MARK: - Inspection

    /// Total number of pending tasks across all tiers.
    public func pendingCount() -> Int {
        queues.values.reduce(0) { $0 + $1.count }
    }

    /// Whether any critical tasks are pending.
    public func hasCriticalTasks() -> Bool {
        !(queues[.critical]?.isEmpty ?? true)
    }

    /// Remove all tasks from the queue.
    public func drainAll() -> [SchedulerTask] {
        var drained: [SchedulerTask] = []
        for tier in [PriorityTier.critical, .userInitiated, .background] {
            drained.append(contentsOf: queues[tier, default: []])
            queues[tier] = []
        }
        return drained
    }
}
