import SwiftUI
import BadgerCore
import BadgerRuntime

// MARK: - Error Presentable Protocol

@MainActor
public protocol ErrorPresentable: View {
    associatedtype ErrorView: View
    func errorView(for error: Error) -> ErrorView
}

// MARK: - Friendly Error Mapper

public struct FriendlyErrorMapper {
    
    /// A Sendable representation of a user-facing error
    public struct FriendlyError: Identifiable, Sendable {
        public let id = UUID()
        public let title: String
        public let message: String
        public let suggestion: String?
        public let icon: String
        public let color: Color
        public let actions: [ErrorAction]
        
        public struct ErrorAction: Identifiable, Sendable {
            public let id = UUID()
            public let title: String
            public let role: ButtonRole?
            // Action closure must be Sendable to cross actor boundaries
            public let action: @Sendable () -> Void
        }
    }
    
    /// Maps a raw Error to a friendly UI representation.
    /// Note: The default actions provided here are mostly placeholders (No-ops) or simple dismissals.
    /// For "Retry" logic, the call site should typically intercept the error or inject the handler.
    public static func map(_ error: Error) -> FriendlyError {
        
        if let appError = error as? AppCoordinatorError {
            return mapAppCoordinatorError(appError)
        }
        
        if let routerError = error as? ShadowRouterError {
            return mapShadowRouterError(routerError)
        }
        
        if let cloudError = error as? CloudInferenceError {
            return mapCloudInferenceError(cloudError)
        }
        
        if let localError = error as? LocalInferenceError {
            return mapLocalInferenceError(localError)
        }
        
        // Generic Fallback
        return FriendlyError(
            title: "Something Went Wrong",
            message: error.localizedDescription,
            suggestion: "Please try again or restart the application.",
            icon: "exclamationmark.triangle",
            color: .orange,
            actions: [
                FriendlyError.ErrorAction(title: "OK", role: .cancel, action: {})
            ]
        )
    }
    
    // MARK: - Specific Mappers
    
    private static func mapAppCoordinatorError(_ error: AppCoordinatorError) -> FriendlyError {
        switch error {
        case .executionFailed(let reason):
            return FriendlyError(
                title: "Couldn't Process Request",
                message: reason,
                suggestion: "Check your connection and try again.",
                icon: "bolt.slash",
                color: .orange,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
            
        case .sanitizationFailed(let reason):
            return FriendlyError(
                title: "Input Blocked",
                message: reason,
                suggestion: "Your input contained restricted patterns.",
                icon: "shield.slash",
                color: .red,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
            
        case .securityViolation(let details):
            return FriendlyError(
                title: "Security Alert",
                message: "Unsafe content detected.",
                suggestion: details,
                icon: "lock.shield",
                color: .red,
                actions: [.init(title: "I Understand", role: .cancel, action: {})]
            )
            
        default:
            return FriendlyError(
                title: "Application Error",
                message: error.localizedDescription,
                suggestion: nil,
                icon: "exclamationmark.circle",
                color: .gray,
                actions: [.init(title: "Dismiss", role: .cancel, action: {})]
            )
        }
    }
    
    private static func mapShadowRouterError(_ error: ShadowRouterError) -> FriendlyError {
        switch error {
        case .allEnginesUnavailable:
            return FriendlyError(
                title: "System Unavailable",
                message: "Neither local nor cloud AI is available.",
                suggestion: "Check your internet connection or download a local model.",
                icon: "network.slash",
                color: .red,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
            
        case .piiRedactionRequired:
            return FriendlyError(
                title: "Privacy Shield Active",
                message: "Personal information was automatically redacted.",
                suggestion: "Your request processed safely with PII removed.",
                icon: "eye.slash",
                color: .blue,
                actions: [.init(title: "Got It", role: .cancel, action: {})]
            )
            
        default:
            return FriendlyError(
                title: "Routing Error",
                message: "Could not route your request.",
                suggestion: error.localizedDescription,
                icon: "arrow.triangle.branch",
                color: .orange,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
        }
    }
    
    private static func mapCloudInferenceError(_ error: CloudInferenceError) -> FriendlyError {
        switch error {
        case .noTokenAvailable:
            return FriendlyError(
                title: "No Cloud Provider",
                message: "You haven't connected a cloud AI provider.",
                suggestion: "Go to Settings to sign in, or use a local model.",
                icon: "cloud.bolt",
                color: .blue,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
        case .rateLimited:
            return FriendlyError(
                title: "Rate Limited",
                message: "Too many requests to the cloud service.",
                suggestion: "Please wait a moment.",
                icon: "clock",
                color: .orange,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
        default:
            return FriendlyError(
                title: "Cloud Error",
                message: error.localizedDescription,
                suggestion: "Check your internet connection.",
                icon: "wifi.exclamationmark",
                color: .orange,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
        }
    }
    
    private static func mapLocalInferenceError(_ error: LocalInferenceError) -> FriendlyError {
        switch error {
        case .modelNotLoaded:
            return FriendlyError(
                title: "No Model Loaded",
                message: "A local model is required for this action.",
                suggestion: "Please download a model in Settings.",
                icon: "cpu",
                color: .blue,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
        case .insufficientVRAM:
            return FriendlyError(
                title: "Out of Memory",
                message: "Your Mac lacks the RAM for this model.",
                suggestion: "Try a smaller model (Quantum/Small).",
                icon: "memorychip",
                color: .red,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
        case .thermalThrottling:
            return FriendlyError(
                title: "Thermal Protection",
                message: "System is too hot for local AI.",
                suggestion: "Allow your Mac to cool down.",
                icon: "thermometer.sun",
                color: .orange,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
        default:
            return FriendlyError(
                title: "Local AI Error",
                message: error.localizedDescription,
                suggestion: nil,
                icon: "exclamationmark.circle",
                color: .orange,
                actions: [.init(title: "OK", role: .cancel, action: {})]
            )
        }
    }
}

// MARK: - Friendly Error View

public struct FriendlyErrorView: View {
    let error: FriendlyErrorMapper.FriendlyError
    let onDismiss: () -> Void
    
    public var body: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(error.color.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: error.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(error.color)
                    .accessibilityHidden(true) // Decorative
            }
            
            // Text Content
            VStack(spacing: 8) {
                Text(error.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(error.message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let suggestion = error.suggestion {
                    Text(suggestion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal)
            
            // Actions
            HStack(spacing: 12) {
                ForEach(error.actions) { action in
                    Button(role: action.role) {
                        action.action()
                        // Ensure button press dismisses the view
                        onDismiss()
                    } label: {
                        Text(action.title)
                    }
                    .buttonStyle(.bordered)
                    .tint(action.role == .destructive ? .red : .blue)
                }
            }
            .padding(.top, 10)
        }
        .padding(30)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 10)
        .frame(maxWidth: 400)
    }
}

// MARK: - Error Alert Modifier

public struct FriendlyErrorAlert: ViewModifier {
    @Binding var error: Error?
    
    public func body(content: Content) -> some View {
        content
            .alert(
                "Error",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                ),
                presenting: error
            ) { error in
                let friendly = FriendlyErrorMapper.map(error)
                
                // Map custom actions to Alert buttons
                ForEach(friendly.actions) { action in
                    Button(action.title, role: action.role) {
                        action.action()
                    }
                }
                
                // Always ensure there is at least one dismiss button
                if friendly.actions.isEmpty {
                    Button("OK", role: .cancel) {}
                }
                
            } message: { error in
                let friendly = FriendlyErrorMapper.map(error)
                Text(friendly.message)
                if let suggestion = friendly.suggestion {
                    Text("\n" + suggestion)
                }
            }
    }
}

public extension View {
    func friendlyErrorAlert(error: Binding<Error?>) -> some View {
        modifier(FriendlyErrorAlert(error: error))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
        FriendlyErrorView(
            error: FriendlyErrorMapper.FriendlyError(
                title: "Connection Lost",
                message: "The AI engine is currently unavailable.",
                suggestion: "Please try again in a few moments.",
                icon: "wifi.slash",
                color: .orange,
                actions: [
                    .init(title: "Retry", role: nil, action: {}),
                    .init(title: "Cancel", role: .cancel, action: {})
                ]
            ),
            onDismiss: {}
        )
    }
    .frame(width: 500, height: 400)
}
