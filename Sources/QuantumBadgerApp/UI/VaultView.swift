import SwiftUI
import QuantumBadgerRuntime

struct VaultView: View {
    let vaultStore: VaultStore
    private let authManager = AuthenticationManager()

    @State private var label: String = ""
    @State private var secret: String = ""
    @State private var revealedSecret: String = ""
    @State private var isShowingSecret: Bool = false
    @State private var authErrorMessage: String?
    @State private var hideAfterDelay: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Secure Items")
                .font(.title)
                .fontWeight(.semibold)

            HStack {
                TextField("Name", text: $label)
                SecureField("Value", text: $secret)
                Button("Save") {
                    guard !label.isEmpty, !secret.isEmpty else { return }
                    vaultStore.storeSecret(label: label, value: secret)
                    label = ""
                    secret = ""
                }
                .buttonStyle(.borderedProminent)
            }

            Toggle("Show once, hide after 10 seconds", isOn: $hideAfterDelay)
                .toggleStyle(.switch)

            if vaultStore.items.isEmpty {
                ContentUnavailableView("No Saved Items", systemImage: "lock", description: Text("Saved items appear here."))
            } else {
                List {
                    ForEach(vaultStore.items) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.label)
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Show") {
                                Task { await revealSecret(for: item) }
                            }
                            .buttonStyle(.bordered)

                            Button("Delete") {
                                vaultStore.remove(item: item)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .privacySensitive()
        .sheet(isPresented: $isShowingSecret) {
            SecureRevealSheet(secret: revealedSecret) {
                revealedSecret = ""
                isShowingSecret = false
            }
        }
        .alert("Can’t Authenticate", isPresented: Binding(
            get: { authErrorMessage != nil },
            set: { _ in authErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authErrorMessage ?? "Please try again.")
        }
    }

    @MainActor
    private func revealSecret(for item: VaultItem) async {
        do {
            let context = try await authManager.authenticate(
                reason: "Authenticate to view a secure item."
            )
            let value = vaultStore.secret(forLabel: item.label, context: context) ?? ""
            context.invalidate()
            revealedSecret = value
            isShowingSecret = true
            if hideAfterDelay {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    revealedSecret = ""
                    isShowingSecret = false
                }
            }
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }
}

private struct SecureRevealSheet: View {
    let secret: String
    let onClose: () -> Void
    @State private var isRevealed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Secure Item")
                .font(.headline)
            if secret.isEmpty {
                Text("No value found.")
                    .font(.body)
            } else if isRevealed {
                Text(secret)
                    .textSelection(.disabled)
                    .font(.body)
            } else {
                Text("Hidden. Tap Reveal to view.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            if !secret.isEmpty {
                Button(isRevealed ? "Hide" : "Reveal") {
                    isRevealed.toggle()
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        .onAppear {
            isRevealed = false
        }
    }
}
