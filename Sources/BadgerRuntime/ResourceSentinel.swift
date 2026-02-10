import Foundation
import AppKit
import Dispatch

/// Proactive resource guards that protect system stability.
///
/// `ResourceSentinel` owns four lifecycle‑bound observers:
///
/// 1. **Heavy App Sentinel** — detects launching of resource‑intensive apps
///    (Xcode, Final Cut Pro, Adobe Premiere) and triggers immediate MLX/Metal
///    eviction via *Yield‑on‑Launch* semantics.
///
/// 2. **Idle‑Unload Sentinel** — evicts MLX/Metal buffers after 30 seconds
///    of inactivity on baseline hardware, freeing ~4 GB of RAM.
///
/// 3. **Memory Pressure Observer** — monitors kernel memory pressure via
///    `DispatchSource.makeMemoryPressureSource` and escalates through deny
///    → flush → full yield.
///
/// 4. **NPU Thermal Watcher** — monitors `ProcessInfo.thermalState` via
///    KVO and throttles or cancels inference on thermal warnings.
public actor ResourceSentinel {

    // MARK: - Types

    /// Delegate protocol for resource eviction callbacks.
    public protocol EvictionDelegate: AnyObject, Sendable {
        func evictLocalModelResources() async
        func flushBuffersAndAuditLogs() async
        func cancelActiveInference() async
        func throttleNPU() async
        /// Notify the user of a critical resource event.
        func notifyUser(_ message: String) async
    }

    /// Known heavy applications.
    public static let heavyAppBundleIDs: Set<String> = [
        "com.apple.dt.Xcode",
        "com.apple.FinalCut",
        "com.adobe.PremierePro",
        "com.adobe.AfterEffects",
        "com.adobe.Photoshop",
        "com.apple.Logic10",
    ]

    // MARK: - State

    private weak var delegate: EvictionDelegate?
    private let scheduler: PriorityScheduler
    private let idleTimeoutNanoseconds: UInt64

    /// Whether the sentinel has been started.
    private var isActive: Bool = false

    /// Handle for the currently running idle timer task.
    private var idleTimerTask: Task<Void, Never>?

    /// Handle for the memory pressure dispatch source.
    private var memoryPressureSource: (any DispatchSourceMemoryPressure)?

    /// Handle for the app‑launch observation task.
    private var appLaunchTask: Task<Void, Never>?

    /// Handle for the thermal observation task.
    private var thermalObservationTask: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - delegate: Callback target for eviction events.
    ///   - scheduler: The priority scheduler for injecting Tier 0 tasks.
    ///   - idleTimeoutSeconds: Seconds of inactivity before MLX eviction.
    ///     Defaults to **30** for baseline 8 GB hardware.
    public init(
        delegate: EvictionDelegate,
        scheduler: PriorityScheduler,
        idleTimeoutSeconds: UInt64 = 30
    ) {
        self.delegate = delegate
        self.scheduler = scheduler
        self.idleTimeoutNanoseconds = idleTimeoutSeconds * 1_000_000_000
    }

    // MARK: - Lifecycle

    /// Start all resource observers.
    public func start() {
        guard !isActive else { return }
        isActive = true
        startHeavyAppSentinel()
        startIdleUnloadSentinel()
        startMemoryPressureObserver()
        startThermalWatcher()
    }

    /// Stop all resource observers and cancel pending tasks.
    public func stop() {
        isActive = false
        idleTimerTask?.cancel()
        idleTimerTask = nil
        appLaunchTask?.cancel()
        appLaunchTask = nil
        thermalObservationTask?.cancel()
        thermalObservationTask = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    /// Reset the idle timer — called on every user interaction or inference.
    public func resetIdleTimer() {
        idleTimerTask?.cancel()
        startIdleTimerTask()
    }

    // MARK: - Heavy App Sentinel

    private func startHeavyAppSentinel() {
        appLaunchTask = Task { [weak self] in
            let center = NSWorkspace.shared.notificationCenter
            let notifications = center.notifications(
                named: NSWorkspace.didLaunchApplicationNotification
            )
            for await notification in notifications {
                guard !Task.isCancelled else { return }
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                   let bundleID = app.bundleIdentifier,
                   Self.heavyAppBundleIDs.contains(bundleID)
            {
                    await self?.handleHeavyAppLaunch(bundleID: bundleID)
                }
            }
        }
    }

    private func handleHeavyAppLaunch(bundleID: String) async {
        await scheduler.enqueue(SchedulerTask(
            tier: .critical,
            label: "HeavyAppSentinel: \(bundleID) launched"
        ))
        // Friendly notice handled by delegate update if needed, but for heavy apps
        // we typically just yield silently or show a small toast.
        // For now, we focus on the requested "Emergency Shutdown" notification.
        await delegate?.evictLocalModelResources()
    }

    // MARK: - Idle‑Unload Sentinel

    private func startIdleUnloadSentinel() {
        startIdleTimerTask()
    }

    private func startIdleTimerTask() {
        idleTimerTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.idleTimeoutNanoseconds)
                guard !Task.isCancelled else { return }
                await self.delegate?.evictLocalModelResources()
            } catch {
                // Task was cancelled — timer reset or sentinel stopped.
            }
        }
    }

    // MARK: - Memory Pressure Observer

    private func startMemoryPressureObserver() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            Task {
                if event.contains(.critical) {
                    await self.handleCriticalMemoryPressure()
                } else if event.contains(.warning) {
                    await self.handleWarningMemoryPressure()
                }
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleWarningMemoryPressure() async {
        await scheduler.enqueue(SchedulerTask(
            tier: .critical,
            label: "MemoryPressure: warning — deny new inference"
        ))
    }

    private func handleCriticalMemoryPressure() async {
        await scheduler.enqueue(SchedulerTask(
            tier: .critical,
            label: "MemoryPressure: critical — full yield"
        ))
        await delegate?.notifyUser("Critical Memory: Saving data and freeing resources to prevent system instability.")
        await delegate?.flushBuffersAndAuditLogs()
        await delegate?.evictLocalModelResources()
    }

    // MARK: - NPU Thermal Watcher

    private func startThermalWatcher() {
        thermalObservationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: ProcessInfo.thermalStateDidChangeNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { return }
                let state = ProcessInfo.processInfo.thermalState
                await self?.handleThermalStateChange(state)
            }
        }
    }

    private func handleThermalStateChange(
        _ state: ProcessInfo.ThermalState
    ) async {
        switch state {
        case .serious:
            await delegate?.throttleNPU()
            await delegate?.notifyUser("System Warm: Slowing down AI to cool down.")
        case .critical:
            await scheduler.enqueue(SchedulerTask(
                tier: .critical,
                label: "ThermalState: critical — cancel and yield"
            ))
            await delegate?.notifyUser("Emergency Shutdown: System is overheating. Saving data and unloading AI to protect hardware.")
            await delegate?.cancelActiveInference()
            await delegate?.flushBuffersAndAuditLogs()
            await delegate?.evictLocalModelResources()
        case .nominal, .fair:
            break
        @unknown default:
            break
        }
    }
}
