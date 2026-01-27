import SwiftUI

struct AuthButtons: View {
    @State private var appleCoordinator = AppleSignInCoordinator()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { try? await signInWithGoogle() }
            } label: {
                Image(systemName: "g.circle.fill").font(.title2)
            }

            Button {
                Task { @MainActor in
                    appleCoordinator.start()
                }
            } label: {
                Image(systemName: "apple.logo").font(.title2)
            }
        }
    }
}
