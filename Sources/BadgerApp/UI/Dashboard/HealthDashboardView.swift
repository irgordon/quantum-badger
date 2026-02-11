import SwiftUI
import BadgerRuntime

/// System health dashboard displaying real‑time runtime metrics.
///
/// All state is driven by ``AppCoordinator/systemStatus`` and
/// rendered entirely on `@MainActor`.
struct HealthDashboardView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(spacing: 16) {
                    memoryCard
                    executionCard
                    thermalCard
                    safeModeCard
                    remoteControlCard
                }
                .padding(20)
            }
        }
        .frame(minWidth: 420, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: "heart.text.clipboard")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("System Health")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Cards

    private var memoryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Memory", systemImage: "memorychip")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    Text("Total RAM")
                    Spacer()
                    Text(formatBytes(coordinator.systemStatus.totalRAMBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Available")
                    Spacer()
                    Text(formatBytes(coordinator.systemStatus.availableRAMBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Model Budget")
                    Spacer()
                    Text(formatBytes(coordinator.systemStatus.localModelBudgetBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory: \(formatBytes(coordinator.systemStatus.totalRAMBytes)) total, \(formatBytes(coordinator.systemStatus.availableRAMBytes)) available, \(formatBytes(coordinator.systemStatus.localModelBudgetBytes)) model budget")
    }

    private var executionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Execution", systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    Text("Location")
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(coordinator.systemStatus.executionLocation == .local
                                  ? Color.green : Color.blue)
                            .frame(width: 8, height: 8)
                        Text(coordinator.systemStatus.executionLocation.rawValue.capitalized)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(coordinator.systemStatus.executionLocation == .local
                     ? "Processing on your device. Data stays local."
                     : "Processing via cloud API. Data leaves this device.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Execution location: \(coordinator.systemStatus.executionLocation.rawValue). \(coordinator.systemStatus.executionLocation == .local ? "Data stays on your device" : "Data is sent to cloud")")
    }

    private var thermalCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Thermal", systemImage: "thermometer.medium")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    Text("State")
                    Spacer()
                    Text(coordinator.systemStatus.thermalState.capitalized)
                        .foregroundStyle(thermalColor)
                }

                HStack {
                    Text("Throttled")
                    Spacer()
                    Image(systemName: coordinator.systemStatus.isThrottled
                          ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(coordinator.systemStatus.isThrottled
                                         ? .orange : .green)
                }

                if coordinator.systemStatus.isThrottled {
                    Text("Performance is reduced to protect your hardware. Processing may be slower than usual.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thermal state: \(coordinator.systemStatus.thermalState). \(coordinator.systemStatus.isThrottled ? "System is thermally throttled" : "No throttling active")")
    }

    private var safeModeCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Safe Mode", systemImage: "cloud.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: coordinator.isSafeModeActive
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(coordinator.isSafeModeActive ? .blue : .secondary)
                    Text(coordinator.isSafeModeActive ? "Cloud Only" : "Off")
                        .foregroundStyle(.secondary)
                }

                if coordinator.isSafeModeActive {
                    Text("All processing is routed to cloud. Local model unloaded to free memory.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Safe mode: \(coordinator.isSafeModeActive ? "active, cloud only" : "off")")
    }

    private var remoteControlCard: some View {
        GroupBox {
            HStack {
                Label("Remote Control", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: coordinator.isRemoteControlEnabled
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(coordinator.isRemoteControlEnabled ? .green : .secondary)
                Text(coordinator.isRemoteControlEnabled ? "Enabled" : "Disabled")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Remote control: \(coordinator.isRemoteControlEnabled ? "enabled" : "disabled")")
    }

    // MARK: - Helpers

    private var thermalColor: Color {
        switch coordinator.systemStatus.thermalState {
        case "critical": return .red
        case "serious": return .orange
        case "fair": return .yellow
        default: return .green
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB", gb)
    }
}
