import SwiftUI

struct SelectedStoreCard: View {
    let title: String
    let address: String?
    let isAddressShown: Bool
    let onToggleAddress: () -> Void
    let onEdit: () -> Void

    let accentSeed: String
    let trailingButtonTitle: String
    let trailingAction: () -> Void

    private var hasAddress: Bool {
        let a = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !a.isEmpty
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {

                Group {
                    if hasAddress {
                        Button(action: onToggleAddress) {
                            titleRow
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in onEdit() }
                        )
                    } else {
                        titleRow
                            .onLongPressGesture(minimumDuration: 0.5) {
                                onEdit()
                            }
                    }
                }

                Text("Selected store")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if isAddressShown, hasAddress, let address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer()

            Button(action: trailingAction) {
                Label(trailingButtonTitle, systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(color(for: accentSeed).opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)

            if hasAddress {
                Image(systemName: isAddressShown ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func color(for seed: String) -> Color {
        let hash = seed.unicodeScalars.reduce(0) { ($0 &* 131) &+ Int($1.value) }
        let palette: [Color] = [.blue, .purple, .indigo, .teal, .mint, .pink, .orange]
        return palette[abs(hash) % palette.count]
    }
}
