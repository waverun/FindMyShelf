import SwiftUI
import UIKit

struct ConfirmImageSheet: View {
    let image: UIImage?
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    @State private var baseScale: CGFloat = 1.0
    @State private var pinchScale: CGFloat = 1.0
    @State private var baseOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    @State private var useZoomedArea: Bool = false
    @State private var didAutoSwitchToZoomMode: Bool = false
    @State private var imageViewportSize: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    private let viewportAspect: CGFloat = 3.0 / 4.0

    private var effectiveScale: CGFloat {
        min(max(baseScale * pinchScale, minScale), maxScale)
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: baseOffset.width + dragOffset.width,
            height: baseOffset.height + dragOffset.height
        )
    }

    private var isActuallyZoomed: Bool {
        effectiveScale > 1.01 || abs(effectiveOffset.width) > 0.5 || abs(effectiveOffset.height) > 0.5
    }

    private var imageToSendPreview: UIImage? {
        guard let image else { return nil }
        if useZoomedArea, isActuallyZoomed, let cropped = cropVisibleArea(from: image) {
            return cropped
        }
        return image
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))

                    if let image {
                        ZoomableImageView(
                            image: image,
                            baseScale: $baseScale,
                            pinchScale: $pinchScale,
                            baseOffset: $baseOffset,
                            dragOffset: $dragOffset,
                            minScale: minScale,
                            maxScale: maxScale,
                            effectiveScale: effectiveScale,
                            effectiveOffset: effectiveOffset,
                            viewportSize: $imageViewportSize
                        )
                        .transition(.opacity)
                    } else {
                        ProgressView("Loading image…")
                            .progressViewStyle(.circular)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(viewportAspect, contentMode: .fit)
                .animation(.easeInOut(duration: 0.25), value: image)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if image != nil {
                    Picker("Photo area", selection: $useZoomedArea) {
                        Text("Use full photo").tag(false)
                        Text("Use zoomed area").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .disabled(!isActuallyZoomed)

                }

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
            .onChange(of: pinchScale) { _, newValue in
                if !didAutoSwitchToZoomMode, newValue > 1.01 {
                    useZoomedArea = true
                    didAutoSwitchToZoomMode = true
                }
            }
            .onChange(of: baseScale) { _, newValue in
                if !didAutoSwitchToZoomMode, newValue > 1.01 {
                    useZoomedArea = true
                    didAutoSwitchToZoomMode = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use photo") {
                        if let imageToSendPreview {
                            onConfirm(imageToSendPreview)
                        } else if let image {
                            onConfirm(image)
                        }
                    }
                    .disabled(image == nil)
                }
            }
        }
    }

    private func normalizedImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: rendererFormat)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private func cropVisibleArea(from image: UIImage) -> UIImage? {
        let normalized = normalizedImage(image)
        guard let cg = normalized.cgImage else { return nil }
        let viewport = imageViewportSize
        guard viewport.width > 1, viewport.height > 1 else { return nil }

        let imageSize = CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))

        let fitScale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)

        let displayedW = fittedSize.width * effectiveScale
        let displayedH = fittedSize.height * effectiveScale

        let topLeftX = (viewport.width - displayedW) / 2 + effectiveOffset.width
        let topLeftY = (viewport.height - displayedH) / 2 + effectiveOffset.height

        let cropX = max(0, (0 - topLeftX) / (fitScale * effectiveScale))
        let cropY = max(0, (0 - topLeftY) / (fitScale * effectiveScale))
        let cropW = min(imageSize.width - cropX, viewport.width / (fitScale * effectiveScale))
        let cropH = min(imageSize.height - cropY, viewport.height / (fitScale * effectiveScale))

        guard cropW > 2, cropH > 2 else { return nil }

        let rect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH).integral
        guard let cropped = cg.cropping(to: rect) else { return nil }

        return UIImage(cgImage: cropped, scale: normalized.scale, orientation: .up)
    }
}

private struct ZoomableImageView: View {
    let image: UIImage

    @Binding var baseScale: CGFloat
    @Binding var pinchScale: CGFloat

    @Binding var baseOffset: CGSize
    @Binding var dragOffset: CGSize

    let minScale: CGFloat
    let maxScale: CGFloat
    let effectiveScale: CGFloat
    let effectiveOffset: CGSize

    @Binding var viewportSize: CGSize

    var body: some View {
        GeometryReader { proxy in
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
                        pinchScale = 1.0
                        baseOffset = .zero
                        dragOffset = .zero
                    }
                }
                .onAppear {
                    viewportSize = proxy.size
                }
                .onChange(of: proxy.size) { _, newSize in
                    viewportSize = newSize
                }
        }
    }

    private var combinedGesture: some Gesture {
        SimultaneousGesture(magnificationGesture, dragGesture)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                pinchScale = value
            }
            .onEnded { value in
                baseScale = min(max(baseScale * value, minScale), maxScale)
                pinchScale = 1.0
                if baseScale <= 1.01 {
                    baseScale = 1.0
                    baseOffset = .zero
                    dragOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard effectiveScale > 1.0 else {
                    dragOffset = .zero
                    return
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard effectiveScale > 1.0 else {
                    baseOffset = .zero
                    dragOffset = .zero
                    return
                }
                baseOffset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
                dragOffset = .zero
            }
    }
}
