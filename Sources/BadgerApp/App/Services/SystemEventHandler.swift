import Foundation
import BadgerCore
import QuantumBadgerRuntime

@MainActor
final class SystemEventHandler {
    private weak var appState: AppState?
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func handle(_ event: SystemEvent) {
        switch event {
        case .networkResponseTruncated(let host):
            handleNetworkResponseTruncated(host)
        case .modelLoadBlocked:
             appState?.feedback.showBanner(message: "Model loading blocked due to memory pressure.", isError: true)
        case .modelLoadRejected(let reason):
            handleModelLoadRejected(reason)
        case .networkCircuitTripped(let host, let cooldownSeconds):
            handleCircuitTripped(host: host, cooldownSeconds: cooldownSeconds)
        case .networkCircuitOpened(let host, let until):
            appState?.openCircuitsStore.handleOpened(host: host, until: until)
        case .networkCircuitClosed(let host):
            appState?.openCircuitsStore.handleClosed(host: host)
        case .decodingSkipped(let count, let source):
            handleDecodingSkipped(count: count, source: source)
        case .memoryWriteNeedsConfirmation(let origin):
            handleMemoryWriteNeedsConfirmation(origin: origin)
        case .toolExecutionFailed(_, let message):
            appState?.feedback.showBanner(message: message, isError: false)
        case .pccConnectionDelay:
            appState?.feedback.showBanner(message: "Securing connection to Private Cloud Compute…", isError: false)
        case .outboundMessageBlocked(let reason):
            handleOutboundMessageBlocked(reason: reason)
        case .systemActionNotice(let message):
            appState?.feedback.showBanner(message: message, isError: false)
        case .modelEvictionRequested(let reason):
            Task { [weak self] in
                guard let self, let appState = self.appState else { return }
                let released = await appState.runtimeCapabilities.orchestrator.releaseRuntimeForMemoryPressure()
                guard released else { return }
                appState.feedback.showToast(reason)
                appState.storageCapabilities.auditLog.record(
                    event: .systemMaintenance("Proactive model eviction: \(reason)")
                )
            }
        case .modelAutoUnloaded(let message):
            appState?.feedback.showToast(message)
        case .thermalThrottlingChanged(let active):
            handleThermalThrottlingChanged(active: active)
        case .thermalEmergencyShutdown(let reason):
            Task { [weak self] in
                await self?.performEmergencyShutdown(reason: reason)
            }
        case .conversationCompacted(let beforeTokens, let afterTokens):
            handleConversationCompacted(beforeTokens: beforeTokens, afterTokens: afterTokens)
        default: break
        }
    }
    
    private func handleNetworkResponseTruncated(_ host: String) {
        appState?.feedback.showBanner(message: "Response from \(host) was too large and was stopped.", isError: true)
    }

    private func handleModelLoadRejected(_ reason: String) {
        appState?.feedback.showBanner(
            message: reason,
            isError: false,
            actionTitle: "Open Models",
            action: { [weak appState] in
                appState?.navigation.selection = .models
            }
        )
    }

    private func handleCircuitTripped(host: String, cooldownSeconds: Int) {
        appState?.feedback.showBanner(
            message: "Network requests to \(host) are paused for \(cooldownSeconds)s after repeated failures.",
            isError: true,
            actionTitle: "Open Settings",
            action: { [weak appState] in
                appState?.navigation.selection = .settings
            }
        )
    }

    private func handleDecodingSkipped(count: Int, source: String?) {
        let sourceLabel = source ?? "results"
        let message = "Skipped \(count) malformed \(sourceLabel.lowercased()) item\(count == 1 ? "" : "s")."
        appState?.feedback.showBanner(message: message, isError: false)
    }

    private func handleMemoryWriteNeedsConfirmation(origin: String) {
        appState?.feedback.showBanner(
            message: "Memory from \(origin) needs confirmation before saving.",
            isError: false,
            actionTitle: "Open Memory",
            action: { [weak appState] in
                appState?.navigation.selection = .settings
                appState?.navigation.settingsSelection = .general
            }
        )
    }

    private func handleOutboundMessageBlocked(reason: String) {
        appState?.feedback.showBanner(
            message: "Message blocked to protect your privacy. \(reason)",
            isError: false,
            actionTitle: "Open Security Center",
            action: { [weak appState] in
                appState?.navigation.selection = .settings
                appState?.navigation.settingsSelection = .security
            }
        )
    }

    private func handleThermalThrottlingChanged(active: Bool) {
        if active {
            appState?.feedback.showBanner(
                message: "Thermal throttling active. MLX tasks are running at lower power to protect your Mac.",
                isError: false,
                actionTitle: "Open Security Center",
                action: { [weak appState] in
                    appState?.navigation.selection = .settings
                    appState?.navigation.settingsSelection = .security
                }
            )
        } else {
            appState?.feedback.showBanner(message: "Thermal throttling cleared. Full performance restored.", isError: false)
        }
    }

    private func handleConversationCompacted(beforeTokens: Int, afterTokens: Int) {
        appState?.feedback.showBanner(
            message: "Context optimized: \(beforeTokens) to \(afterTokens) tokens.",
            isError: false
        )
    }

    private func performEmergencyShutdown(reason: String) async {
        guard let appState = appState else { return }
        await appState.runtimeCapabilities.orchestrator.cancelActiveGeneration()
        await TaskPlanner.shared.forcePersist()
        await LocalMLXInference.shared.purgeContext()
        await appState.storageCapabilities.auditLog.flush()
        await appState.storageCapabilities.memoryManager.flush()
        await PendingMessageStore.shared.flush()
        appState.feedback.showBanner(
            message: "Emergency shutdown engaged. \(reason)",
            isError: true,
            actionTitle: "Open Security Center",
            action: { [weak appState] in
                appState?.navigation.selection = .settings
                appState?.navigation.settingsSelection = .security
            }
        )
    }
}

