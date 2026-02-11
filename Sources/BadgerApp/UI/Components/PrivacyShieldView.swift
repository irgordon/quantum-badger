import SwiftUI

struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .font(.title2)
                Text("Hidden for privacy")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
}
