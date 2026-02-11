import SwiftUI

struct MemoryToastView: View {
    let toast: MemoryToastState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "memorychip.fill")
                .foregroundStyle(.indigo)
            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: toast.id)
    }
}
