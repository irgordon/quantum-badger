import SwiftUI
import BadgerRuntime

/// Glanceable, read‑only menu bar status surface.
///
/// Design contract:
/// - **No actor access** — consumes only the nonisolated `SystemStatus` snapshot
/// - **No mutation** — no toggles, no buttons that change runtime state
/// - **No async work** — no `await`, no timers, no background tasks
/// - **No inference triggers** — purely informational
///
/// Data freshness is managed by `AppCoordinator`, which pushes snapshots
/// on `@MainActor` every 5 seconds. The menu bar simply reads `@Published`
/// state.
struct MenuBarView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Status Rows

            statusSection

            Divider()
                .padding(.vertical, 4)

            // MARK: - Execution Mode Bar

            executionModeBar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()
                .padding(.vertical, 4)

            // MARK: - Protection States

            protectionSection

            Divider()
                .padding(.vertical, 4)

            // MARK: - Deep Link

            Button {
                openWindow(id: "health-dashboard")
            } label: {
                Label("Open System Health Dashboard", systemImage: "heart.text.clipboard")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 280)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Memory Usage
            statusRow(
                label: "Available RAM",
                value: formatBytes(coordinator.systemStatus.availableRAMBytes),
                color: memoryColor
            )
            .accessibilityLabel("Available RAM: \(formatBytes(coordinator.systemStatus.availableRAMBytes))")

            // Conversation Size
            HStack {
                Text("Context")
                    .font(.system(.body, design: .default))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(coordinator.systemStatus.conversationTokenCount) tokens")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if coordinator.systemStatus.isConversationCompacted {
                        Image(systemName: "archivebox.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Conversation compacted")
                    }
                }
            }

            // Active Model
            statusRow(
                label: "Active Model",
                value: activeModelLabel,
                color: modelColor
            )
            .accessibilityLabel("Active model: \(activeModelLabel)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Execution Mode Bar

    private var executionModeBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Local")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Cloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    // Fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(executionBarGradient)
                        .frame(
                            width: executionBarWidth(totalWidth: geometry.size.width),
                            height: 6
                        )
                }
            }
            .frame(height: 6)
            .accessibilityLabel("Execution: \(activeModelLabel)")
        }
    }

    // MARK: - Protection States

    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if coordinator.systemStatus.isSafeModeActive {
                protectionRow(
                    icon: "cloud.fill",
                    label: "Safe Mode Active",
                    color: .blue
                )
            }

            if coordinator.systemStatus.isThrottled {
                protectionRow(
                    icon: "thermometer.high",
                    label: "Thermally Throttled",
                    color: .orange
                )
            }

            thermalRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var thermalRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "thermometer.medium")
                .font(.caption)
                .foregroundStyle(thermalColor)
            Text("Thermal: \(coordinator.systemStatus.thermalState.capitalized)")
                .font(.system(.body, design: .default))
                .foregroundStyle(.primary)
            Spacer()
        }
        .accessibilityLabel("Thermal state: \(coordinator.systemStatus.thermalState)")
    }

    // MARK: - Reusable Components

    private func statusRow(
        label: String,
        value: String,
        color: Color
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .default))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private func protectionRow(
        icon: String,
        label: String,
        color: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(label)
                .font(.system(.body, design: .default))
                .foregroundStyle(.primary)
            Spacer()
        }
        .accessibilityLabel(label)
    }

    // MARK: - Computed Properties

    private var activeModelLabel: String {
        switch coordinator.systemStatus.executionLocation {
        case .local: return "Local (NPU/GPU)"
        case .cloud: return "Cloud API"
        }
    }

    private var memoryColor: Color {
        let available = coordinator.systemStatus.availableRAMBytes
        let total = coordinator.systemStatus.totalRAMBytes
        guard total > 0 else { return .secondary }
        let ratio = Double(available) / Double(total)
        if ratio > 0.4 { return .secondary }
        if ratio > 0.2 { return .orange }
        return .red
    }

    private var modelColor: Color {
        coordinator.systemStatus.executionLocation == .local ? .green : .blue
    }

    private var thermalColor: Color {
        switch coordinator.systemStatus.thermalState {
        case "critical": return .red
        case "serious": return .orange
        case "fair": return .yellow
        default: return .green
        }
    }

    private var executionBarGradient: LinearGradient {
        let isLocal = coordinator.systemStatus.executionLocation == .local
        return LinearGradient(
            colors: isLocal ? [.green, .green.opacity(0.6)] : [.blue.opacity(0.6), .blue],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func executionBarWidth(totalWidth: CGFloat) -> CGFloat {
        coordinator.systemStatus.executionLocation == .local
            ? totalWidth * 0.5 // Filled left half for local
            : totalWidth       // Filled full bar (right emphasis) for cloud
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "Unavailable" }
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB", gb)
    }
}
