import SwiftUI

struct BannerView: View {
    let text: String
    let isError: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)

            Text(text)
                .font(.footnote)
                .lineLimit(2)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isError ? Color.red.opacity(0.18) : Color.green.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(radius: 10, y: 6)
    }
}
