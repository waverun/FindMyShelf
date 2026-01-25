import SwiftUI

struct ActionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
                    .shadow(radius: 10, y: 5)
            )
    }
}
