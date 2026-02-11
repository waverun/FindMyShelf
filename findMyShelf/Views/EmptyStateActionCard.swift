import SwiftUI

struct EmptyStateActionCard: View {
    let title: String
    let icon: String

    let prefixText: String
    let buttonSystemImage: String
    let buttonA11yLabel: String
    let suffixText: String

    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(prefixText)

                    Button(action: action) {
                        Image(systemName: buttonSystemImage)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [
                                        AppColors.logoOrangeLight,
                                        AppColors.logoOrangeDark
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: AppColors.logoOrangeDark.opacity(0.35),
                                    radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                    .opacity(isEnabled ? 1 : 0.4)
                    .disabled(!isEnabled)
                    
//                    Button(action: action) {
//                        Image(systemName: buttonSystemImage)
//                            .font(.subheadline.weight(.semibold))
//                            .padding(.horizontal, 10)
//                            .padding(.vertical, 6)
//                            .background(.thinMaterial)
//                            .clipShape(Capsule())
//                    }
//                    .buttonStyle(.plain)
//                    .accessibilityLabel(buttonA11yLabel)
//                    .opacity(isEnabled ? 1 : 0.4)
//                    .disabled(!isEnabled)

                    Text(suffixText)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
