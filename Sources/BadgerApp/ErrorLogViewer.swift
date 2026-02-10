import SwiftUI
import BadgerCore

/// Read‑only error log viewer for the Settings > Error Log tab.
///
/// Displays entries in chronological order with filtering by
/// category and time range. No mutation — safe under repeated access.
///
/// ## HIG Compliance
/// - Plain‑language summaries only
/// - No raw stack traces by default
/// - Copy/Export for user inspection
/// - VoiceOver reads entries in logical order
struct ErrorLogViewer: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var entries: [ErrorEntry] = []
    @State private var selectedCategory: AppLogger.Category? = nil
    @State private var selectedTimeRange: TimeRange = .allTime

    enum TimeRange: String, CaseIterable {
        case lastHour = "Last Hour"
        case today = "Today"
        case allTime = "All Time"

        var sinceDate: Date? {
            switch self {
            case .lastHour:
                return Date().addingTimeInterval(-3600)
            case .today:
                return Calendar.current.startOfDay(for: Date())
            case .allTime:
                return nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters
            filterBar
                .padding(12)

            Divider()

            // Entry list
            if entries.isEmpty {
                emptyState
            } else {
                entryList
            }

            Divider()

            // Footer with count and export
            footerBar
                .padding(12)
        }
        .task {
            await loadEntries()
        }
        .onChange(of: selectedCategory) { _, _ in
            Task { await loadEntries() }
        }
        .onChange(of: selectedTimeRange) { _, _ in
            Task { await loadEntries() }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Category", selection: $selectedCategory) {
                Text("All").tag(AppLogger.Category?.none)
                ForEach(AppLogger.Category.allCases, id: \.self) { cat in
                    Text(cat.rawValue.capitalized).tag(AppLogger.Category?.some(cat))
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Picker("Time", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Spacer()
        }
    }

    // MARK: - List

    private var entryList: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    severityBadge(entry.severity)
                    Text(entry.category.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.summary)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(entry.severity.rawValue): \(entry.summary). \(entry.category.rawValue). \(entry.timestamp.formatted())"
            )
        }
        .listStyle(.inset)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("No events to display")
                .font(.headline)
            Text("System events will appear here when they occur.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Text("\(entries.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button {
                exportLog()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(entries.isEmpty)
        }
    }

    // MARK: - Severity Badge

    private func severityBadge(_ severity: AppLogger.Severity) -> some View {
        let (icon, color) = severityVisuals(severity)
        return Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func severityVisuals(_ severity: AppLogger.Severity) -> (String, Color) {
        switch severity {
        case .info: return ("info.circle.fill", .blue)
        case .warning: return ("exclamationmark.triangle.fill", .orange)
        case .protectiveAction: return ("shield.checkered", .purple)
        }
    }

    // MARK: - Data Loading

    private func loadEntries() async {
        let filter = ErrorLogFilter(
            category: selectedCategory,
            since: selectedTimeRange.sinceDate
        )
        entries = await coordinator.errorLog.entries(filter: filter)
    }

    // MARK: - Export

    private func exportLog() {
        Task {
            guard let data = await coordinator.errorLog.exportAsJSON() else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "quantum_badger_error_log.json"
            let result = await panel.begin()
            if result == .OK, let url = panel.url {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
