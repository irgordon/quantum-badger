import SwiftUI

struct BannerView: View {
    let banner: BannerState

    var body: some View {
        HStack(spacing: 12) {
            Text(banner.message)
                .font(.callout)
                .foregroundColor(.white)
            if let title = banner.actionTitle, let action = banner.action {
                Button(title) {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(banner.isError ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
        )
        .shadow(radius: 6)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(), value: banner.id)
    }
}
