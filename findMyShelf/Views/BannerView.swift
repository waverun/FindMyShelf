import SwiftUI

struct BannerView: View {
    let text: String
    let isError: Bool
    let actionTitle: String?
    let onAction: (() -> Void)?
    let onTap: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)

            Text(text)
                .font(.footnote)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                if let actionTitle, let onAction {
                    Button(actionTitle, action: onAction)
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.bold())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isError ? Color.red.opacity(0.26) : Color.green.opacity(0.24))
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}
