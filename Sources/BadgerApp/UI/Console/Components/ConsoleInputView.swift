import SwiftUI

struct ConsoleInputView: View {
    @Binding var prompt: String
    @Binding var allowPublicCloud: Bool
    let isGenerating: Bool
    let onMakePlan: () -> Void
    let onAsk: () -> Void
    let onStop: () -> Void
    let onSearchFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Describe what you want to do", text: $prompt)
                Button("Make a Plan") {
                    onMakePlan()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                
                Button("Ask") {
                    onAsk()
                }
                
                Button("Stop Generation") {
                    onStop()
                }
                .disabled(!isGenerating)
                
                Button("Search Files") {
                    onSearchFiles()
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Use public cloud for this request", isOn: $allowPublicCloud)
                Text("Public cloud runs outside this Mac. Only enable for non‑sensitive requests.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}
