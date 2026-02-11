import Foundation
import Combine
import SwiftUI
import Observation

/// A simple model to hold our toast data
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: ToastStyle
    
    enum ToastStyle {
        case memory, info, warning
    }
}

@MainActor
@Observable
final class NotificationManager {
    static let shared = NotificationManager()
    var currentToast: Toast?
    
    func show(message: String, style: Toast.ToastStyle = .info) {
        withAnimation(.spring()) {
            currentToast = Toast(message: message, style: style)
        }
        
        // Auto-dismiss after 4 seconds
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(.easeInOut) {
                if currentToast?.message == message {
                    currentToast = nil
                }
            }
        }
    }
}

struct ToastView: View {
    let toast: Toast
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
            
            Text(toast.message)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial) // Modern macOS blur
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: 400)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private var iconName: String {
        switch toast.style {
        case .memory: return "memorychip.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    
    private var iconColor: Color {
        switch toast.style {
        case .memory: return .purple
        case .info: return .blue
        case .warning: return .orange
        }
    }
}
