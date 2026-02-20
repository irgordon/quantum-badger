import SwiftUI
import BadgerCore
import BadgerRuntime

public struct CloudAccountsSettingsView: View {
    @State private var viewModel = CloudAccountsViewModel()
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                providersSection
                infoSection
            }
            .padding()
        }
        .background(Color(.windowBackgroundColor))
        .navigationTitle("Cloud Accounts")
        .sheet(item: $viewModel.selectedProviderForAuth) { provider in
            ProviderAuthSheet(provider: provider, viewModel: viewModel)
        }
        .alert("Disconnect Provider?", isPresented: $viewModel.showDisconnectConfirmation, presenting: viewModel.providerToDisconnect) { provider in
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task { await viewModel.disconnectProvider(provider) }
            }
        } message: { provider in
            Text("This will remove your \(provider.displayName) credentials.")
        }
        .alert("Error", isPresented: $viewModel.showError, presenting: viewModel.currentError) { error in
            Button("OK") {}
            if error.isRetryable {
                Button("Retry") {
                    if let provider = viewModel.lastAttemptedProvider {
                        viewModel.authenticate(provider: provider)
                    }
                }
            }
        } message: { error in
            Text(error.message)
            if let suggestion = error.recoverySuggestion {
                Text(suggestion).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await viewModel.loadProviderStatuses() }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Cloud AI Providers").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Connect providers to enable cloud-based AI capabilities").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }
    
    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Available Providers").font(.headline)
                Spacer()
                if viewModel.isLoading { ProgressView().scaleEffect(0.8) }
            }
            
            LazyVStack(spacing: 12) {
                ForEach(viewModel.providerStatuses) { status in
                    ProviderStatusCard(status: status, onConnect: { viewModel.authenticate(provider: status.provider) }, onDisconnect: { viewModel.requestDisconnect(status.provider) }, onTest: { await viewModel.testConnection(status.provider) })
                }
            }
        }
        .padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your API keys are stored securely in the Secure Enclave.", systemImage: "lock.shield").font(.caption)
            Label("Data is only sent to connected providers when you choose cloud inference.", systemImage: "arrow.up.arrow.down").font(.caption)
            Button("Connect with SSO (OAuth)") {
                NotificationCenter.default.post(name: .badgerShowCloudSSORequested, object: nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding().background(Color(.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

public struct ProviderStatus: Identifiable, Sendable {
    public let id = UUID()
    public let provider: CloudProvider
    public var isConnected: Bool
    public var isAuthenticated: Bool
    public var lastTested: Date?
    public var testResult: TestResult?
    
    public enum TestResult: Sendable {
        case success(latency: TimeInterval)
        case failure(message: String)
    }
    
    public var displayStatus: String {
        isAuthenticated ? "Connected" : (isConnected ? "Auth Required" : "Not Connected")
    }
}

struct ProviderStatusCard: View {
    let status: ProviderStatus
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onTest: () async -> Void
    @State private var isTesting = false
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(status.provider.brandColor.opacity(0.1)).frame(width: 56, height: 56)
                Image(systemName: status.provider.iconName).font(.title2).foregroundStyle(status.provider.brandColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(status.provider.displayName).font(.headline)
                    if status.isAuthenticated { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption) }
                }
                Text(status.displayStatus).font(.caption).foregroundStyle(status.isAuthenticated ? .green : .secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if status.isAuthenticated {
                    Button { Task { isTesting = true; await onTest(); isTesting = false } } label: { 
                        if isTesting {
                            ProgressView().scaleEffect(0.6).frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "bolt.horizontal")
                        }
                    }.buttonStyle(.borderless)
                    Button { onDisconnect() } label: { Image(systemName: "xmark.circle").foregroundStyle(.red) }.buttonStyle(.borderless)
                } else {
                    Button("Connect") { onConnect() }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
        .padding().background(Color(.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ProviderAuthSheet: View {
    let provider: CloudProvider
    @ObservedObject var viewModel: CloudAccountsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(provider.brandColor.opacity(0.1)).frame(width: 80, height: 80)
                        Image(systemName: provider.iconName).font(.system(size: 40)).foregroundStyle(provider.brandColor)
                    }
                    Text("Connect \(provider.displayName)").font(.title2).fontWeight(.bold)
                    Text("Enter your API key to enable capabilities").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding().frame(maxWidth: .infinity).background(.ultraThinMaterial)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How to get your API key:").font(.headline)
                            ForEach(0..<provider.apiKeyInstructions.count, id: \.self) { index in
                                let instruction = provider.apiKeyInstructions[index]
                                HStack(alignment: .top, spacing: 8) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption); Text(instruction).font(.subheadline) }
                            }
                            Link("Open \(provider.displayName) API Dashboard", destination: provider.dashboardURL).font(.subheadline).padding(.top, 8)
                        }
                        .padding().background(Color(.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key").font(.subheadline).fontWeight(.medium)
                            SecureField("Enter your API key", text: $viewModel.apiKeyInput).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                            if let error = viewModel.validationError { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red) }
                        }
                        
                        HStack(spacing: 8) { Image(systemName: "lock.shield").foregroundStyle(.green); Text("Your API key will be encrypted and stored in the Secure Enclave.").font(.caption).foregroundStyle(.secondary) }
                        .padding().background(Color.green.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding()
                }
                
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                    Spacer()
                    Button("Connect") {
                        Task { if await viewModel.validateAndConnect(provider: provider) { dismiss() } }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.apiKeyInput.isEmpty || viewModel.isValidating)
                }
                .padding().background(.ultraThinMaterial)
            }
        }
        .frame(minWidth: 500, minHeight: 500)
    }
}

@MainActor
public final class CloudAccountsViewModel: ObservableObject {
    @Published public var providerStatuses: [ProviderStatus] = []
    @Published public var isLoading = false
    @Published public var showError = false
    @Published public var currentError: AuthError?
    @Published public var showDisconnectConfirmation = false
    @Published public var providerToDisconnect: CloudProvider?
    @Published public var selectedProviderForAuth: CloudProvider?
    @Published public var lastAttemptedProvider: CloudProvider?
    @Published public var apiKeyInput = ""
    @Published public var validationError: String?
    @Published public var isValidating = false
    
    private let keyManager = KeyManager()
    private let cloudService = CloudInferenceService()
    
    public func loadProviderStatuses() async {
        isLoading = true
        defer { isLoading = false }
        
        let providers: [CloudProvider] = [.anthropic, .openAI, .google]
        let keyManager = self.keyManager
        let cloudService = self.cloudService

        let results = await withTaskGroup(of: ProviderStatus.self) { group in
            for provider in providers {
                group.addTask {
                    let hasToken = await keyManager.hasToken(for: provider)

                    let testResult: ProviderStatus.TestResult?
                    if hasToken {
                        do {
                            let startTime = Date()
                            _ = try await cloudService.generateMini(prompt: "Hello", provider: provider)
                            testResult = .success(latency: Date().timeIntervalSince(startTime))
                        } catch {
                            testResult = .failure(message: error.localizedDescription)
                        }
                    } else {
                        testResult = nil
                    }

                    return ProviderStatus(
                        provider: provider,
                        isConnected: hasToken,
                        isAuthenticated: hasToken && testResult != nil,
                        lastTested: hasToken ? Date() : nil,
                        testResult: testResult
                    )
                }
            }

            var statuses: [ProviderStatus] = []
            for await status in group {
                statuses.append(status)
            }
            return statuses
        }

        providerStatuses = results.sorted { p1, p2 in
            let index1 = providers.firstIndex(of: p1.provider) ?? Int.max
            let index2 = providers.firstIndex(of: p2.provider) ?? Int.max
            return index1 < index2
        }
    }
    
    public func authenticate(provider: CloudProvider) {
        lastAttemptedProvider = provider
        apiKeyInput = ""
        validationError = nil
        selectedProviderForAuth = provider
    }
    
    public func validateAndConnect(provider: CloudProvider) async -> Bool {
        isValidating = true
        validationError = nil
        defer { isValidating = false }
        
        guard !apiKeyInput.isEmpty else { validationError = "API key is required"; return false }
        guard apiKeyInput.count >= 10 else { validationError = "API key appears too short"; return false }
        
        do {
            try await keyManager.storeToken(apiKeyInput, for: provider)
            let testResult = await testProviderConnection(provider)
            if let index = providerStatuses.firstIndex(where: { $0.provider == provider }) {
                providerStatuses[index].isConnected = true
                providerStatuses[index].isAuthenticated = testResult != nil
                providerStatuses[index].lastTested = Date()
                providerStatuses[index].testResult = testResult
            }
            return testResult != nil
        } catch {
            validationError = "Failed to save: \(error.localizedDescription)"
            return false
        }
    }
    
    public func requestDisconnect(_ provider: CloudProvider) {
        providerToDisconnect = provider
        showDisconnectConfirmation = true
    }
    
    public func disconnectProvider(_ provider: CloudProvider) async {
        do {
            try await keyManager.deleteToken(for: provider)
            if let index = providerStatuses.firstIndex(where: { $0.provider == provider }) {
                providerStatuses[index].isConnected = false
                providerStatuses[index].isAuthenticated = false
                providerStatuses[index].testResult = nil
            }
        } catch {
            currentError = AuthError(message: "Failed to disconnect", recoverySuggestion: "Try again", isRetryable: true)
            showError = true
        }
    }
    
    public func testConnection(_ provider: CloudProvider) async {
        let result = await testProviderConnection(provider)
        if let index = providerStatuses.firstIndex(where: { $0.provider == provider }) {
            providerStatuses[index].lastTested = Date()
            providerStatuses[index].testResult = result
        }
    }
    
    private func testProviderConnection(_ provider: CloudProvider) async -> ProviderStatus.TestResult? {
        do {
            let startTime = Date()
            _ = try await cloudService.generateMini(prompt: "Hello", provider: provider)
            return .success(latency: Date().timeIntervalSince(startTime))
        } catch { return .failure(message: error.localizedDescription) }
    }
    
    public struct AuthError: Identifiable {
        public let id = UUID()
        public let message: String
        public let recoverySuggestion: String?
        public let isRetryable: Bool
    }
}

extension CloudProvider {
    public var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .google: return "Google"
        case .applePCC: return "Apple PCC"
        }
    }
    
    public var iconName: String {
        switch self {
        case .anthropic: return "a.circle.fill"
        case .openAI: return "o.circle.fill"
        case .google: return "g.circle.fill"
        case .applePCC: return "apple.logo"
        }
    }
    
    public var brandColor: Color {
        switch self {
        case .anthropic: return .orange
        case .openAI: return .green
        case .google: return .blue
        case .applePCC: return .gray
        }
    }
    
    public var dashboardURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
        case .google: return URL(string: "https://makersuite.google.com/app/apikey")!
        case .applePCC: return URL(string: "https://apple.com")!
        }
    }
    
    public var apiKeyInstructions: [String] {
        switch self {
        case .anthropic: return ["Go to Anthropic Console", "Navigate to API Keys", "Click 'Create Key'", "Copy and paste here"]
        case .openAI: return ["Go to OpenAI Platform", "Navigate to API Keys", "Click 'Create new secret key'", "Copy immediately"]
        case .google: return ["Go to Google AI Studio", "Navigate to API Keys", "Click 'Create API Key'", "Copy and paste here"]
        case .applePCC: return ["Uses device authentication"]
        }
    }
}

#Preview {
    CloudAccountsSettingsView().frame(minWidth: 700, minHeight: 500)
}
