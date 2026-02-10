import SwiftUI
import UIKit

struct ConfirmImageSheet: View {
    let image: UIImage?
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(3/4, contentMode: .fit)

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .transition(.opacity)
                    } else {
                        ProgressView("Loading image…")
                            .progressViewStyle(.circular)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: image)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Text("Use this photo?")
                    .font(.headline)

                Text("Privacy: the photo is used only to extract text. " +
                     "The image itself is not stored.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                
                Text("The app will analyze the aisle sign and add an aisle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Confirm photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use photo") {
                        if let image { onConfirm(image) }
                    }
                    .disabled(image == nil)
                }
            }
        }
    }
}
