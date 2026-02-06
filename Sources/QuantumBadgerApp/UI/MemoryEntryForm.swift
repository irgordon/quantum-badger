import SwiftUI
import QuantumBadgerRuntime

struct MemoryEntryForm: View {
    let memoryManager: MemoryManager
    private let authManager = AuthenticationManager()

    @State private var trustLevel: MemoryTrustLevel = .level1UserAuthored
    @State private var content: String = ""
    @State private var sourceType: MemorySource = .user
    @State private var sourceDetail: String = "User"
    @State private var isConfirmed: Bool = true
    @State private var shouldExpire: Bool = false
    @State private var expiryMinutes: Int = 60
    @State private var errorMessage: String?
    @State private var containsSensitiveData: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Memory")
                .font(.headline)

            Picker("Trust level", selection: $trustLevel) {
                ForEach(MemoryTrustLevel.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: trustLevel) { _, newValue in
                switch newValue {
                case .level0Ephemeral:
                    sourceType = .user
                    isConfirmed = false
                    shouldExpire = true
                case .level1UserAuthored:
                    sourceType = .user
                    isConfirmed = true
                case .level2UserConfirmed:
                    isConfirmed = false
                case .level3Observational:
                    sourceType = .model
                    isConfirmed = false
                    shouldExpire = true
                case .level4Summary:
                    sourceType = .model
                    isConfirmed = false
                case .level5External:
                    sourceType = .tool
                    isConfirmed = false
                }
            }

            TextField("Content", text: $content)
                .onChange(of: content) { _, newValue in
                    let scan = MemoryPIIScanner.scan(newValue)
                    containsSensitiveData = scan.containsSensitiveData
                }
            if containsSensitiveData {
                Label("Sensitive details detected. This memory can’t be saved.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            Picker("Source", selection: $sourceType) {
                ForEach(MemorySource.allCases) { item in
                    Text(item.rawValue.capitalized).tag(item)
                }
            }
            .pickerStyle(.menu)
            HStack {
                TextField("Source detail", text: $sourceDetail)
                    .textFieldStyle(.roundedBorder)
                Menu("Suggestions") {
                    ForEach(sourceSuggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            sourceDetail = suggestion
                        }
                    }
                }
            }

            Toggle("Confirmed by user", isOn: $isConfirmed)
                .disabled(trustLevel == .level0Ephemeral || trustLevel == .level2UserConfirmed)

            Toggle("Expire automatically", isOn: $shouldExpire)

            if shouldExpire {
                Stepper("Expires \(expiryDescription)", value: $expiryMinutes, in: 5...1440, step: 5)
            }

            Button("Save Memory") {
                saveEntry()
            }
            .buttonStyle(.bordered)
            .disabled(content.isEmpty)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func saveEntry() {
        if containsSensitiveData {
            errorMessage = "Memory contains sensitive details and cannot be stored."
            return
        }
        let expiresAt: Date? = shouldExpire ? Date().addingTimeInterval(TimeInterval(expiryMinutes * 60)) : nil
        let entry = MemoryEntry(
            trustLevel: trustLevel,
            content: content,
            sourceType: sourceType,
            sourceDetail: sourceDetail,
            isConfirmed: isConfirmed,
            confirmedAt: isConfirmed ? Date() : nil,
            expiresAt: expiresAt
        )
        switch memoryManager.addEntry(entry, source: .userAction) {
        case .success:
            content = ""
            errorMessage = nil
        case .needsConfirmation:
            Task { await confirmAndStore(entry) }
        case .failed(let error):
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func confirmAndStore(_ entry: MemoryEntry) async {
        do {
            _ = try await authManager.authenticate(reason: "Confirm this memory item.")
            let result = memoryManager.confirmAndStore(entry)
            switch result {
            case .success:
                content = ""
                errorMessage = nil
            case .needsConfirmation:
                errorMessage = "Confirmation is required to save this item."
            case .failed(let error):
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var expiryDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let interval = TimeInterval(expiryMinutes * 60)
        return formatter.localizedString(fromTimeInterval: interval)
    }

    private var sourceSuggestions: [String] {
        ["Console", "Local Search", "Web Summary", "PDF Review", "User Note"]
    }
}
