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
                        ZoomableImageView(image: image)
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

private struct ZoomableImageView: View {
    let image: UIImage

    @State private var baseScale: CGFloat = 1.0
    @GestureState private var pinchScale: CGFloat = 1.0

    @State private var baseOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0

    private var effectiveScale: CGFloat {
        min(max(baseScale * pinchScale, minScale), maxScale)
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: baseOffset.width + dragOffset.width,
            height: baseOffset.height + dragOffset.height
        )
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(effectiveScale)
            .offset(effectiveOffset)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(combinedGesture)
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    baseScale = 1.0
                    baseOffset = .zero
                }
            }
    }

    private var combinedGesture: some Gesture {
        SimultaneousGesture(magnificationGesture, dragGesture)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                baseScale = min(max(baseScale * value, minScale), maxScale)
                if baseScale <= 1.01 {
                    baseScale = 1.0
                    baseOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                guard effectiveScale > 1.0 else {
                    state = .zero
                    return
                }
                state = value.translation
            }
            .onEnded { value in
                guard effectiveScale > 1.0 else {
                    baseOffset = .zero
                    return
                }
                baseOffset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
    }
}
