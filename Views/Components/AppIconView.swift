import SwiftUI

struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .inset(by: 8)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 2)

            Image(systemName: "doc.on.clipboard.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(28)
        }
    }
}