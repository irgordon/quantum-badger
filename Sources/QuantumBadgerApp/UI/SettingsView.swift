import SwiftUI
import QuantumBadgerRuntime

struct SettingsView: View {
    let securityCapabilities: SecurityCapabilities
    let auditLog: AuditLog
    let exportAction: @MainActor () async -> Void
    let modelRegistry: ModelRegistry
    let modelSelection: ModelSelectionStore
    let resourcePolicy: ResourcePolicyStore
    let reachability: NetworkReachabilityMonitor
    let bookmarkStore: BookmarkStore
    let memoryManager: MemoryManager
    let untrustedParsingPolicy: UntrustedParsingPolicyStore
    let messagingPolicy: MessagingPolicyStore
    let webFilterStore: WebFilterStore
    let openCircuitsStore: OpenCircuitsStore
    private let keychain = KeychainStore()

    @State private var allowFileWrites: Bool = false
    @State private var allowedWebDomainsText: String = ""
    @State private var networkSessionMinutes: Int = 10
    @State private var endpointDrafts: [EndpointDraft] = []
    @State private var isSyncingFromDrafts: Bool = false
    @State private var pendingHostsText: String?
    @State private var hostsDebounceTask: Task<Void, Never>?
    @State private var redactionInput: String = ""
    @State private var redactionOutput: String = ""
    @State private var redactionHasSensitive: Bool = false
    @State private var showMemoryDump: Bool = false
    @State private var showAuditDump: Bool = false
    @State private var showPolicyDump: Bool = false
    @State private var showNetworkDump: Bool = false
    @State private var contactNameDraft: String = ""
    @State private var contactHandleDraft: String = ""
    @State private var conversationKeyDraft: String = ""
    @State private var webFilterPatternDraft: String = ""
    @State private var webFilterTypeDraft: WebFilterType = .word
    @State private var allowedDomainDraft: String = ""
    @State private var webFilterTestInput: String = ""
    @State private var webFilterTestOutput: String = ""

    var body: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings")
                        .font(.title)
                        .fontWeight(.semibold)

                GroupBox("Access & Privacy") {
                    Toggle("Allow Quantum Badger to change files", isOn: $allowFileWrites)
                        .onChange(of: allowFileWrites) { _, newValue in
                            if newValue {
                                Task { await securityCapabilities.policy.grant(.filesystemWrite) }
                            } else {
                                Task { await securityCapabilities.policy.revoke(.filesystemWrite) }
                            }
                        }
                    Text("Only the folders you choose are used, and everything stays on this Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Toggle("Protect sensitive details", isOn: Binding(
                        get: { modelRegistry.limits.maxTemperature >= 0 },
                        set: { _ in }
                    ))
                    .disabled(true)
                    Text("Sensitive details are automatically masked before sending to online services.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Text("Trusted Contacts")
                        .font(.headline)
                    Text("Messages are only drafted for people you trust.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        TextField("Name", text: $contactNameDraft)
                        TextField("Handle (email or phone)", text: $contactHandleDraft)
                        TextField("Conversation key", text: $conversationKeyDraft)
                        Button("Add") {
                            messagingPolicy.addContact(
                                name: contactNameDraft,
                                handle: contactHandleDraft,
                                conversationKey: conversationKeyDraft
                            )
                            contactNameDraft = ""
                            contactHandleDraft = ""
                            conversationKeyDraft = ""
                        }
                        .buttonStyle(.bordered)
                        .disabled(contactNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || contactHandleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if messagingPolicy.trustedContacts.isEmpty {
                        Text("No trusted contacts yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        List {
                            ForEach(messagingPolicy.trustedContacts) { contact in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(contact.name)
                                        Text(contact.handle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let key = contact.conversationKey, !key.isEmpty {
                                            Text("Conversation: \(key)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button("Remove") {
                                        messagingPolicy.removeContact(contact)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .frame(minHeight: 120)
                    }

                    Stepper(
                        "Max messages per minute: \(messagingPolicy.maxMessagesPerMinute)",
                        value: Binding(
                            get: { messagingPolicy.maxMessagesPerMinute },
                            set: { messagingPolicy.setMaxMessagesPerMinute($0) }
                        ),
                        in: 1...20,
                        step: 1
                    )
                    Text("Limits how often drafts can be created to prevent accidental spamming.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                GroupBox("Online Access") {
                    TextField("Allowed websites (comma-separated)", text: $allowedWebDomainsText)
                    Text("Online access is off by default and is restricted to the sites you allow.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    HStack {
                        Text("Network type:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(networkTypeLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    ForEach(NetworkPurpose.allCases) { purpose in
                        Toggle(purpose.displayName, isOn: Binding(
                            get: { securityCapabilities.networkPolicy.isPurposeEnabled(purpose) },
                            set: { enabled in
                                if enabled {
                                    securityCapabilities.networkPolicy.enablePurpose(purpose, for: networkSessionMinutes)
                                } else {
                                    securityCapabilities.networkPolicy.setPurpose(purpose, enabled: false)
                                }
                            }
                        ))
                    }

                    Stepper("Allow for: \(networkSessionMinutes) minutes", value: $networkSessionMinutes, in: 1...180, step: 1)
                        .onChange(of: networkSessionMinutes) { _, newValue in
                            securityCapabilities.networkPolicy.setDefaultSessionMinutes(newValue)
                        }

                    Toggle("Do not auto-switch on expensive networks", isOn: Binding(
                        get: { securityCapabilities.networkPolicy.avoidAutoSwitchOnExpensive },
                        set: { securityCapabilities.networkPolicy.setAvoidAutoSwitchOnExpensive($0) }
                    ))

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Advanced Website Rules")
                            .font(.headline)
                        Text("Use these only if you need finer control for a specific website.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach($endpointDrafts) { $draft in
                            EndpointRow(draft: $draft) {
                                endpointDrafts.removeAll { $0.id == draft.id }
                                syncEndpointsFromDrafts()
                            }
                            .onChange(of: draft.host) { _, _ in syncEndpointsFromDrafts() }
                            .onChange(of: draft.methodsText) { _, _ in syncEndpointsFromDrafts() }
                            .onChange(of: draft.pathsText) { _, _ in syncEndpointsFromDrafts() }
                            .onChange(of: draft.allowRedirects) { _, _ in syncEndpointsFromDrafts() }
                            .onChange(of: draft.requiresAppleTrust) { _, _ in syncEndpointsFromDrafts() }
                            .onChange(of: draft.pinsText) { _, _ in syncEndpointsFromDrafts() }
                            .onChange(of: draft.requiredPurpose) { _, _ in syncEndpointsFromDrafts() }
                        }

                        Button("Add Website Rule") {
                            endpointDrafts.append(EndpointDraft())
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Content Filters")
                            .font(.headline)
                        Text("Hide specific words or patterns before results reach the assistant.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("Filter pattern", text: $webFilterPatternDraft)
                            Picker("Type", selection: $webFilterTypeDraft) {
                                ForEach(WebFilterType.allCases) { type in
                                    Text(type.rawValue.capitalized).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                            Button("Add") {
                                webFilterStore.addFilter(pattern: webFilterPatternDraft, type: webFilterTypeDraft)
                                webFilterPatternDraft = ""
                            }
                            .buttonStyle(.bordered)
                            .disabled(webFilterPatternDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if webFilterStore.filters.isEmpty {
                            Text("No filters yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            List {
                                ForEach(webFilterStore.filters) { rule in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(rule.pattern)
                                            Text(rule.type.rawValue.uppercased())
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button("Remove") {
                                            webFilterStore.removeFilter(rule)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .frame(minHeight: 120)
                        }

                        Text("Test Filters")
                            .font(.headline)
                        TextField("Paste sample text to test", text: $webFilterTestInput, axis: .vertical)
                            .lineLimit(3...6)
                        Button("Test Filter") {
                            webFilterTestOutput = testWebFilters(webFilterTestInput)
                        }
                        .buttonStyle(.bordered)
                        if !webFilterTestOutput.isEmpty {
                            TextEditor(text: .constant(webFilterTestOutput))
                                .font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 120)
                                .disabled(true)
                                .privacySensitive()
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Strict Mode (allowlist only)", isOn: Binding(
                            get: { webFilterStore.strictModeEnabled },
                            set: { webFilterStore.setStrictMode($0) }
                        ))
                        Text("When enabled, Quantum Badger only reads from allowed domains.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Allowed domain (e.g. github.com, *.edu)", text: $allowedDomainDraft)
                            Button("Add") {
                                webFilterStore.addAllowedDomain(allowedDomainDraft)
                                allowedDomainDraft = ""
                            }
                            .buttonStyle(.bordered)
                            .disabled(allowedDomainDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if webFilterStore.allowedDomains.isEmpty {
                            Text("No domains added.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            List {
                                ForEach(webFilterStore.allowedDomains, id: \.self) { domain in
                                    HStack {
                                        Text(domain)
                                        Spacer()
                                        Button("Remove") {
                                            webFilterStore.removeAllowedDomain(domain)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .frame(minHeight: 120)
                        }
                    }
                }

                GroupBox("Performance") {
                    let check = SystemCheck.evaluate(minMemoryGB: resourcePolicy.policy.minAvailableMemoryGB)
                    Text("Available memory: \(check.memoryGB) GB")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Stepper(
                        "Warn me below: \(resourcePolicy.policy.minAvailableMemoryGB) GB",
                        value: Binding(
                            get: { resourcePolicy.policy.minAvailableMemoryGB },
                            set: { resourcePolicy.setMinAvailableMemoryGB($0) }
                        ),
                        in: 2...64,
                        step: 1
                    )

                    if check.memoryGB < resourcePolicy.policy.minAvailableMemoryGB {
                        Text("Your Mac may struggle with larger models right now.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                GroupBox("Offline Mode") {
                    Toggle("Hide cloud models when offline", isOn: Binding(
                        get: { modelSelection.hideCloudModelsWhenOffline },
                        set: { modelSelection.setHideCloudModelsWhenOffline($0) }
                    ))
                    Text("When you lose internet access, cloud-only models are hidden.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Offline fallback model", selection: Binding(
                        get: { modelSelection.offlineFallbackModelId },
                        set: { modelSelection.setOfflineFallbackModel($0) }
                    )) {
                        Text("None").tag(UUID?.none)
                        ForEach(modelRegistry.localModels()) { model in
                            Text(model.name).tag(UUID?.some(model.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if !reachability.isReachable {
                        Text("Offline now. The selected model will be used automatically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                GroupBox("Model Prompt Rules") {
                    let localModels = modelRegistry.localModels()
                    if localModels.isEmpty {
                        Text("No local models available.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        List {
                            ForEach(localModels) { model in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.name)
                                        .font(.headline)
                                    Stepper(
                                        "Max prompt chars: \(model.maxPromptChars)",
                                        value: Binding(
                                            get: { model.maxPromptChars },
                                            set: { newValue in
                                                var updated = model
                                                updated.maxPromptChars = newValue
                                                modelRegistry.updateModel(updated)
                                            }
                                        ),
                                        in: 500...8000,
                                        step: 250
                                    )
                                    Toggle(
                                        "Protect sensitive details",
                                        isOn: Binding(
                                            get: { model.redactSensitivePrompts },
                                            set: { newValue in
                                                var updated = model
                                                updated.redactSensitivePrompts = newValue
                                                modelRegistry.updateModel(updated)
                                            }
                                        )
                                    )
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .frame(minHeight: 140)
                    }
                }

                GroupBox("Folders") {
                    if bookmarkStore.entries.isEmpty {
                        Text("No folders selected.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        List {
                            ForEach(bookmarkStore.entries) { entry in
                                HStack {
                                    Text(entry.name)
                                    Spacer()
                                    Button("Remove") {
                                        bookmarkStore.removeEntry(entry)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .frame(minHeight: 120)
                    }
                    Button("Add Folder") {
                        Task { await addFolderBookmarks() }
                    }
                    .buttonStyle(.bordered)
                }

                GroupBox("Memory") {
                    Toggle("Remember my habits", isOn: Binding(
                        get: { true },
                        set: { _ in }
                    ))
                    .disabled(true)
                    Text("Memory stays on this Mac and is always editable.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    MemoryEntryForm(memoryManager: memoryManager)
                    MemoryTimelineView(memoryManager: memoryManager)
                }

                GroupBox("Manage Cloud Keys") {
                    let cloudModels = modelRegistry.models.filter { $0.isCloud }
                    if cloudModels.isEmpty {
                        Text("No cloud models configured.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        List {
                            ForEach(cloudModels) { model in
                                HStack {
                                    Text(model.name)
                                    Spacer()
                                    Button("Remove") {
                                        removeCloudModel(model)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .frame(minHeight: 120)
                    }
                }

                GroupBox("Activity Export") {
                    Button("Export Activity Log") {
                        Task { await exportAction() }
                    }
                    .buttonStyle(.bordered)
                    Text("Exports are encrypted by default.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                GroupBox("Network Activity Summary") {
                    let summary = NetworkAuditSummary(entries: auditLog.entries)
                    if summary.totalAttempts == 0 {
                        Text("No network activity recorded yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(NetworkPurpose.allCases) { purpose in
                                let counts = summary.counts(for: purpose)
                                HStack {
                                    Text(purpose.displayName)
                                    Spacer()
                                    Text("\(counts.allowed) allowed")
                                        .foregroundColor(.secondary)
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text("\(counts.denied) denied")
                                        .foregroundColor(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Temporarily paused hosts")
                            .font(.headline)
                        if openCircuitsStore.openCircuits.isEmpty {
                            Text("No hosts are currently paused.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(openCircuitsStore.openCircuits) { circuit in
                                HStack {
                                    Text(circuit.host)
                                    Spacer()
                                    Text(remainingCooldownText(until: circuit.until))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .tabItem {
            Label("General", systemImage: "gearshape")
        }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Advanced")
                        .font(.title)
                        .fontWeight(.semibold)

                    GroupBox("Endpoint Pins") {
                        if securityCapabilities.networkPolicy.endpointsSnapshot().isEmpty {
                            Text("No endpoints configured.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            List {
                                ForEach(securityCapabilities.networkPolicy.endpointsSnapshot(), id: \.host) { endpoint in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(endpoint.host)
                                            .font(.headline)
                                        Text("Purpose: \(endpoint.requiredPurpose.displayName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if endpoint.pinnedSPKIHashes.isEmpty {
                                            Text("No SPKI pins configured.")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            ForEach(endpoint.pinnedSPKIHashes, id: \.self) { pin in
                                                Text(pin)
                                                    .font(.caption2)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .frame(minHeight: 160)
                        }
                    }

                    GroupBox("Redaction Debugger") {
                        TextField("Paste text to test redaction", text: $redactionInput, axis: .vertical)
                            .lineLimit(3...6)
                        Button("Run Redaction") {
                            let result = PromptRedactor.redact(redactionInput)
                            redactionOutput = result.redactedText
                            redactionHasSensitive = result.hadSensitiveData
                        }
                        .buttonStyle(.bordered)

                        if !redactionOutput.isEmpty {
                            Text("Redacted output:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: .constant(redactionOutput))
                                .font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 120)
                                .disabled(true)
                                .privacySensitive()
                            Text(redactionHasSensitive ? "Sensitive content detected." : "No sensitive content detected.")
                                .font(.caption)
                                .foregroundColor(redactionHasSensitive ? .orange : .secondary)
                        }
                    }

                    GroupBox("Raw Data") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("View Memory Store") { showMemoryDump = true }
                                .buttonStyle(.bordered)
                            Button("View Audit Log") { showAuditDump = true }
                                .buttonStyle(.bordered)
                            Button("View Policy Dump") { showPolicyDump = true }
                                .buttonStyle(.bordered)
                            Button("View Network Policy") { showNetworkDump = true }
                                .buttonStyle(.bordered)
                        }
                    }

                    GroupBox("Parser Resilience") {
                        Toggle("Retry parser after a crash", isOn: Binding(
                            get: { untrustedParsingPolicy.retryEnabled },
                            set: { untrustedParsingPolicy.setRetryEnabled($0) }
                        ))
                        Text("If the parser stops unexpectedly, Quantum Badger can try again once.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
            }
            .sheet(isPresented: $showMemoryDump) {
                SecureJSONViewer(title: "Memory Store") {
                    await memoryTimelineJSON()
                }
            }
            .sheet(isPresented: $showAuditDump) {
                SecureJSONViewer(title: "Audit Log") {
                    auditLogJSON
                }
            }
            .sheet(isPresented: $showPolicyDump) {
                SecureJSONViewer(title: "Policy Dump") {
                    await policySnapshotJSON()
                }
            }
            .sheet(isPresented: $showNetworkDump) {
                SecureJSONViewer(title: "Network Policy") {
                    networkPolicyJSON
                }
            }
        }
        .tabItem {
            Label("Advanced", systemImage: "wrench.and.screwdriver")
        }
        .onAppear {
            Task {
                allowFileWrites = await securityCapabilities.policy.hasGrant(.filesystemWrite)
            }
            networkSessionMinutes = securityCapabilities.networkPolicy.defaultSessionMinutes
            allowedWebDomainsText = networkHostsString(securityCapabilities.networkPolicy.endpointsSnapshot())
            endpointDrafts = securityCapabilities.networkPolicy.endpointsSnapshot().map { EndpointDraft(from: $0) }
        }
        .onChange(of: allowedWebDomainsText) { _, newValue in
            scheduleHostsSync(newValue)
        }
    }

    private func syncEndpointsFromDrafts() {
        let endpoints = endpointDrafts.compactMap { $0.toEndpoint() }
        securityCapabilities.networkPolicy.setEndpoints(endpoints)
        isSyncingFromDrafts = true
        allowedWebDomainsText = networkHostsString(endpoints)
        isSyncingFromDrafts = false
    }

    private func scheduleHostsSync(_ value: String) {
        if isSyncingFromDrafts { return }
        pendingHostsText = value
        hostsDebounceTask?.cancel()
        hostsDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let pending = pendingHostsText else { return }
            await MainActor.run {
                applyHostsSync(pending)
            }
        }
    }

    private func applyHostsSync(_ value: String) {
        guard !isSyncingFromDrafts else { return }
        let endpoints = parseHosts(from: value)
        securityCapabilities.networkPolicy.setEndpoints(endpoints)
        endpointDrafts = endpoints.map { EndpointDraft(from: $0) }
    }

    private func removeCloudModel(_ model: LocalModel) {
        if !modelRegistry.removeModel(model) {
            return
        }
        let keyLabel = "cloud-api-key-\(model.id.uuidString)"
        try? keychain.deleteSecret(label: keyLabel)
        try? keychain.deleteSecretOwner(label: keyLabel)
    }

    @MainActor
    private func addFolderBookmarks() async {
        let urls = await FolderPickerPresenter.present()
        guard !urls.isEmpty else { return }
        let entries: [BookmarkEntry] = urls.compactMap { url in
            do {
                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                return BookmarkEntry(name: url.lastPathComponent, bookmarkData: bookmarkData)
            } catch {
                return nil
            }
        }
        bookmarkStore.addEntries(entries)
    }

    private var networkTypeLabel: String {
        if reachability.isExpensive {
            return "Expensive"
        }
        if reachability.isConstrained {
            return "Low Data Mode"
        }
        if reachability.isReachable {
            return "Normal"
        }
        return "Offline"
    }

    private var auditLogJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(auditLog.entries),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }

    private var networkPolicyJSON: String {
        let snapshot = securityCapabilities.networkPolicy.endpointsSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "[]"
    }

    private func memoryTimelineJSON() async -> String {
        let entries = await memoryManager.loadTimelineEntries()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "[]"
    }

    private func policySnapshotJSON() async -> String {
        let snapshot = await securityCapabilities.policy.snapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }

    private func testWebFilters(_ text: String) -> String {
        var result = text
        for filter in webFilterStore.activeFilters() {
            switch filter.type {
            case .word:
                result = result.replacingOccurrences(
                    of: filter.pattern,
                    with: "[FILTERED]",
                    options: .caseInsensitive
                )
            case .regex:
                if let regex = try? NSRegularExpression(pattern: filter.pattern) {
                    let range = NSRange(location: 0, length: result.utf16.count)
                    result = regex.stringByReplacingMatches(
                        in: result,
                        options: [],
                        range: range,
                        withTemplate: "[FILTERED]"
                    )
                }
            }
        }
        return result
    }

    private func remainingCooldownText(until: Date) -> String {
        let remaining = max(0, Int(until.timeIntervalSinceNow))
        if remaining <= 0 {
            return "Resuming shortly"
        }
        if remaining < 60 {
            return "Resuming in \(remaining)s"
        }
        let minutes = Int(ceil(Double(remaining) / 60.0))
        return "Resuming in \(minutes)m"
    }
}

private struct SecureJSONViewer: View {
    let title: String
    let fetcher: () async -> String
    @State private var content: String = "Loading..."

    var body: some View {
        VStack {
            TextEditor(text: .constant(content))
                .font(.system(.caption, design: .monospaced))
                .privacySensitive()
                .task {
                    content = await fetcher()
                }
        }
        .padding()
        .navigationTitle(title)
    }
}

private struct EndpointDraft: Identifiable, Hashable {
    let id = UUID()
    var host: String = ""
    var methodsText: String = "GET"
    var pathsText: String = "/"
    var allowRedirects: Bool = false
    var requiresAppleTrust: Bool = false
    var pinsText: String = ""
    var requiredPurpose: NetworkPurpose = .webContentRetrieval

    init() { }

    init(from endpoint: NetworkEndpointPolicy) {
        host = endpoint.host
        methodsText = endpoint.allowedMethods.joined(separator: ", ")
        pathsText = endpoint.allowedPathPrefixes.joined(separator: ", ")
        allowRedirects = endpoint.allowRedirects
        requiresAppleTrust = endpoint.requiresAppleTrust
        pinsText = endpoint.pinnedSPKIHashes.joined(separator: ", ")
        requiredPurpose = endpoint.requiredPurpose
    }

    func toEndpoint() -> NetworkEndpointPolicy? {
        let normalizedHost = normalizeHost(host) ?? ""
        guard !normalizedHost.isEmpty else { return nil }
        let methods = splitCSV(methodsText, defaultValues: ["GET"]).map { $0.uppercased() }
        let paths = splitCSV(pathsText, defaultValues: ["/"]).filter { $0.hasPrefix("/") }
        let pins = splitCSV(pinsText, defaultValues: [])
        return NetworkEndpointPolicy(
            host: normalizedHost,
            allowedMethods: methods.isEmpty ? ["GET"] : methods,
            allowedPathPrefixes: paths.isEmpty ? ["/"] : paths,
            allowRedirects: allowRedirects,
            requiresAppleTrust: requiresAppleTrust,
            pinnedSPKIHashes: pins,
            requiredPurpose: requiredPurpose
        )
    }
}

private struct EndpointRow: View {
    @Binding var draft: EndpointDraft
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Website", text: $draft.host)
                Button("Remove", action: onRemove)
                    .buttonStyle(.bordered)
            }
            Picker("Purpose", selection: $draft.requiredPurpose) {
                ForEach(NetworkPurpose.allCases) { purpose in
                    Text(purpose.displayName).tag(purpose)
                }
            }
            .pickerStyle(.menu)
            HStack {
                TextField("Allowed methods (e.g. GET, POST)", text: $draft.methodsText)
                TextField("Allowed paths (e.g. /v1, /api)", text: $draft.pathsText)
            }
            HStack {
                Toggle("Allow redirects", isOn: $draft.allowRedirects)
                Toggle("Apple‑trusted only", isOn: $draft.requiresAppleTrust)
            }
            TextField("Certificate pins (base64, comma-separated)", text: $draft.pinsText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.windowBackgroundColor)))
    }
}

private struct NetworkAuditSummary {
    private let entries: [AuditEntry]
    private let recentWindow: TimeInterval = 60 * 60 * 24 * 7

    init(entries: [AuditEntry]) {
        self.entries = entries
    }

    var totalAttempts: Int {
        recentNetworkEntries().count
    }

    func counts(for purpose: NetworkPurpose) -> (allowed: Int, denied: Int) {
        let items = recentNetworkEntries().filter { $0.event.purpose == purpose }
        let allowed = items.filter { $0.event.allowed == true }.count
        let denied = items.filter { $0.event.allowed == false }.count
        return (allowed, denied)
    }

    private func recentNetworkEntries() -> [AuditEntry] {
        let cutoff = Date().addingTimeInterval(-recentWindow)
        return entries.filter { $0.event.kind == .networkAttempt && $0.event.timestamp >= cutoff }
    }
}

private func splitCSV(_ input: String, defaultValues: [String]) -> [String] {
    let parts = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    if parts.isEmpty {
        return defaultValues
    }
    return parts.filter { !$0.isEmpty }
}

private func parseHosts(from input: String) -> [NetworkEndpointPolicy] {
    let rawParts = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let hosts = rawParts.compactMap { normalizeHost(String($0)) }
    return Array(Set(hosts)).sorted().map { host in
        NetworkEndpointPolicy(host: host)
    }
}

private func normalizeHost(_ value: String) -> String? {
    if value.isEmpty { return nil }
    if let url = URL(string: value), let host = url.host {
        return host.lowercased()
    }
    if value.contains("/") { return nil }
    return value.lowercased()
}

private func networkHostsString(_ endpoints: [NetworkEndpointPolicy]) -> String {
    endpoints.map { $0.host }.sorted().joined(separator: ", ")
}
