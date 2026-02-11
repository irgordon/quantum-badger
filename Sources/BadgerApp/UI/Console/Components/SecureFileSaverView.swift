import SwiftUI
import BadgerCore
import BadgerRuntime

struct SecureFileSaverView: View {
    @Binding var locationName: String
    @Binding var contents: String
    @Binding var locationReference: VaultReference?
    @Binding var notice: String?
    @Binding var isPickerPresented: Bool
    let onWriteFile: () -> Void

    var body: some View {
        GroupBox("Save to File") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose where to save a report or code snippet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let notice {
                    HStack(spacing: 8) {
                        Text(notice)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Fix…") {
                            isPickerPresented = true
                        }
                        .buttonStyle(.link)
                    }
                }
                HStack {
                    TextField("Save location label", text: $locationName)
                    Button(locationReference == nil ? "Choose File…" : "Change…") {
                        isPickerPresented = true
                    }
                    .buttonStyle(.bordered)
                }
                TextEditor(text: $contents)
                    .frame(minHeight: 80)
                Button("Write File") {
                    onWriteFile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(locationReference == nil || contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .privacySensitive()
    }
}
