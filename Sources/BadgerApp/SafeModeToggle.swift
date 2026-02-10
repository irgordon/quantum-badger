import SwiftUI
import BadgerRuntime
import Observation

struct SafeModeToggle: View {
    @Bindable var policyStore = ResourcePolicyStore.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $policyStore.isSafeModeEnabled) {
                VStack(alignment: .leading) {
                    Text("Cloud-Only Safe Mode")
                        .font(.headline)
                    Text("Pins local RAM usage to zero by offloading all tasks to ChatGPT. Best for heavy video editing or 8GB hardware.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            
            if policyStore.isSafeModeEnabled {
                Label("Local NPU & RAM are currently protected.", systemImage: "bolt.shield.fill")
                    .font(.caption2.bold())
                    .foregroundColor(.purple)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(10)
    }
}
