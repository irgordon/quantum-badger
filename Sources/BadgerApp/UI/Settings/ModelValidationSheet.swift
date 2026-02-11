import SwiftUI
import BadgerRuntime

/// Sheet presented after custom model file selection.
///
/// Displays real‑time validation progress and results. The sheet
/// is driven entirely by `AppCoordinator` published state —
/// no actor access occurs here.
struct ModelValidationSheet: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Image(systemName: "shield.checkered")
                .font(.system(size: 40))
                .foregroundStyle(.accent)

            Text("Model Safety Check")
                .font(.title2)
                .fontWeight(.semibold)

            // State
            if coordinator.isValidatingModel {
                validatingView
            } else if let result = coordinator.lastValidationResult {
                resultView(result)
            } else {
                // Idle — shouldn't normally be shown
                Text("Waiting for model file…")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions
            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 400, minHeight: 300)
    }

    // MARK: - Validating

    @ViewBuilder
    private var validatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Checking model safety…")
                .font(.headline)

            Text("This may take a moment for large files. You can close this sheet — validation will continue in the background.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private func resultView(_ result: ModelValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            checkRow(
                label: "Memory Fit",
                passed: result.fitsInMemory,
                detail: result.fitsInMemory
                    ? "This model fits within your available memory."
                    : "This model may exceed your available memory."
            )

            checkRow(
                label: "File Safety",
                passed: result.isSafe,
                detail: result.isSafe
                    ? "No unsafe payloads detected."
                    : "This file contains potentially unsafe content."
            )

            checkRow(
                label: "Verified Source",
                passed: result.isVerified,
                detail: result.isVerified
                    ? "Model comes from a trusted source."
                    : "This model is unverified. Use with caution."
            )

            Divider()

            HStack {
                Text("Estimated RAM:")
                Spacer()
                Text(formatBytes(result.estimatedRAMBytes))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if result.canLoad {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Ready to select and load")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func checkRow(label: String, passed: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "—" }
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return String(format: "~%.1f GB", gb)
    }
}
