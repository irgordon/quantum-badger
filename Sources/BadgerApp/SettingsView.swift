import SwiftUI
import BadgerCore
import BadgerRuntime

struct SettingsView: View {
    let securityCapabilities: SecurityCapabilities
    let auditLog: AuditLog
    let exportAction: () async -> Void
    let modelRegistry: ModelRegistry
    let modelSelection: ModelSelectionStore
    let resourcePolicy: ResourcePolicy
    let reachability: NetworkReachabilityMonitor
    let bookmarkStore: BookmarkStore
    let memoryManager: MemoryController
    let untrustedParsingPolicy: UntrustedParsingPolicy
    let identityPolicy: IdentityPolicy
    let auditRetentionPolicy: AuditRetentionPolicy
    let messagingPolicy: MessagingPolicy
    let messagingInboxStore: MessagingInboxStore
    let pairingCoordinator: PairingCoordinator
    let webFilterStore: WebFilterStore
    let openCircuitsStore: OpenCircuitsStore
    let intentOrchestrator: IntentOrchestrator
    let intentProviderSelection: IntentProviderSelection
    let healthCheckStore: HealthCheckStore
    let identityRecoveryManager: IdentityRecoveryManager
    let conversationHistoryStore: ConversationHistoryStore
    let appIntentScanner: AppIntentScanner
    let systemOperatorCapabilities: SystemOperatorCapabilities
    @Binding var selectedTab: SettingsSelection
    @Binding var memoryDeepLinkId: String?
    @Binding var goalDeepLinkId: String?
    @Binding var showPairingSheet: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            Form {
                Section("General") {
                    Text("General settings here")
                }
            }
            .tabItem { Label("General", systemImage: "gear") }
            .tag(SettingsSelection.general)

            Form {
                Section("Security") {
                    Text("Security settings here")
                }
            }
            .tabItem { Label("Security", systemImage: "lock") }
            .tag(SettingsSelection.security)
            
            Form {
                Section("Models") {
                    Text("Model settings here")
                }
            }
            .tabItem { Label("Models", systemImage: "cpu") }
            .tag(SettingsSelection.models)
        }
        .padding()
    }
}
