import SwiftUI

struct StorePosterCard: View {
    let title: String
    let subtitle: String?
    let colorIndex: Int
    let isHighlighted: Bool
    let badgeText: String?
    let buttonTitle: String
    let buttonAction: () -> Void

    var body: some View {
        let baseColor = color(for: colorIndex)

        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [baseColor.opacity(0.95), baseColor.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isHighlighted ? .white.opacity(0.85) : .white.opacity(0.18),
                                      lineWidth: isHighlighted ? 2 : 1)
                )
                .shadow(radius: isHighlighted ? 16 : 12, y: isHighlighted ? 8 : 6)
                .scaleEffect(isHighlighted ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHighlighted)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {

                    if let badgeText {
                        Text(badgeText)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.22))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Button(buttonTitle, action: buttonAction)
                    .font(.subheadline.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.25))
            }
            .padding(16)
        }
        .frame(width: 280, height: 170)
        .accessibilityElement(children: .combine)
    }

    private func color(for index: Int) -> Color {
        let palette: [Color] = [
            .blue, .purple, .indigo, .teal, .mint, .pink, .orange
        ]
        return palette[index % palette.count]
    }
}
