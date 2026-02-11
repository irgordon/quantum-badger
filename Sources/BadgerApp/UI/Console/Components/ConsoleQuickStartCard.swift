import SwiftUI

struct ConsoleQuickStartCard: View {
    @AppStorage("showConsoleQuickStart") private var isVisible: Bool = true
    
    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Quick Start Guide", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            isVisible = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss permanently")
                }
                
                Divider()
                
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRow(
                            icon: "memorychip",
                            title: "Keeping your Mac snappy",
                            description: "Local AI lives in your RAM. Closing heavy apps like Xcode or Photoshop helps the model run faster."
                        )
                        
                        FeatureRow(
                            icon: "pin.fill", // Assuming pin feature existed or is planned
                            title: "Manual Context Control",
                            description: "Right-click messages to 'Pin' them. Pinned messages stay in memory even when the conversation gets long."
                        )
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRow(
                            icon: "stop.circle",
                            title: "You are in control",
                            description: "Hit the Stop button at any time to interrupt the agent. You don't have to wait for it to finish."
                        )
                        
                        // Embedded Safety Toggle
                        SafeModeToggle()
                            .padding(.top, 4)
                    }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
