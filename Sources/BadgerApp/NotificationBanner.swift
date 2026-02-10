import SwiftUI

/// Auto‑dismissing top‑edge banner for ``UserNotice`` presentation.
///
/// Applied as a `ViewModifier` to the root content view.
/// The banner slides in from the top, shows for the notice's
/// configured duration, then slides out.
///
/// ## HIG Compliance
/// - Non‑blocking — does not interrupt primary workflows
/// - Subtle — no aggressive flashing or animation
/// - VoiceOver — announced immediately upon appearance
/// - Text‑primary — color is a secondary cue only
struct NotificationBanner: ViewModifier {
    @Binding var notice: UserNotice?

    @State private var isVisible: Bool = false
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let notice, isVisible {
                bannerContent(notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityLabel("\(notice.title). \(notice.detail)")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .onChange(of: notice) { _, newNotice in
            if let newNotice {
                show(newNotice)
            }
        }
    }

    private func bannerContent(_ notice: UserNotice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: notice.severity))
                .font(.body)
                .foregroundStyle(iconColor(for: notice.severity))

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(notice.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Lifecycle

    private func show(_ notice: UserNotice) {
        dismissTask?.cancel()

        isVisible = true

        dismissTask = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(notice.dismissAfterSeconds * 1_000_000_000)
                )
                isVisible = false
                // Small delay to let animation complete before clearing.
                try await Task.sleep(nanoseconds: 400_000_000)
                self.notice = nil
            } catch {
                // Cancelled — view was dismissed early.
            }
        }
    }

    // MARK: - Visual Mapping

    private func iconName(for severity: UserNotice.Severity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .protectiveAction: return "shield.checkered"
        }
    }

    private func iconColor(for severity: UserNotice.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .protectiveAction: return .purple
        }
    }
}

// MARK: - View Extension

extension View {
    /// Attach a notification banner that presents ``UserNotice`` instances.
    func notificationBanner(notice: Binding<UserNotice?>) -> some View {
        modifier(NotificationBanner(notice: notice))
    }
}
