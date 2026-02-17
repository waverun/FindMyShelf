import SwiftUI
import FirebaseAuth

struct AuthButtons: View {
    @Binding var showAccountSheet: Bool
    @Binding var showEmailLoginSheet: Bool
    @State private var appleCoordinator = AppleSignInCoordinator()
    @State private var showLogoutConfirm = false
    @State private var authTick = 0
    
//    var user = Auth.auth().currentUser

    var user: User? { Auth.auth().currentUser }
    var isLoggedIn: Bool {
        user != nil
    }
    
//    var providerIcon: String? {
//        guard let providerId = user?.providerData.first?.providerID else {
//            return nil
//        }
//        
//        switch providerId {
//            case "google.com":
//                return "g.circle.fill"
//            case "apple.com":
//                return "applelogo"
//            default:
//                return nil
//        }
//    }

    var providerIcon: String? {
        guard let providerId = user?.providerData.first?.providerID else {
            return nil
        }

        switch providerId {
            case "google.com":
                return "g.circle.fill"

            case "apple.com":
                return "applelogo"

            case "password":
                return "envelope.fill"   // ← זה מה שחסר

            default:
                return nil
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            
            // Login buttons (only when logged out)
            if !isLoggedIn {
                Button {
                    Task {
                        try? await signInWithGoogle()
                        authTick += 1
                    }
                } label: {
                    Image(systemName: "g.circle.fill")
                        .font(.title2)
                }

                Button {
                    showEmailLoginSheet = true
                } label: {
//                    Image(systemName: "envelope")
                    Image(systemName: "envelope")
                        .font(.system(size: 15))
                        .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))                }

                Button {
                    Task { @MainActor in
                        appleCoordinator.start()
                        authTick += 1
                    }
                } label: {
                    Image(systemName: "applelogo")
                        .font(.title2)
                }
            }
            
            // Avatar + provider badge
            Button {
                showAccountSheet = true
//                if isLoggedIn {
//                    showLogoutConfirm = true
//                }
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        isLoggedIn ? .blue : .gray,
                        isLoggedIn ? .cyan : .gray.opacity(0.6)
                    )
                    .overlay(alignment: .bottomLeading) {
                        if isLoggedIn, let providerIcon {
                            Image(systemName: providerIcon)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(3)
                                .background(.ultraThinMaterial, in: Circle())
                            // Nudge slightly so it sits just inside the avatar
                                .offset(x: -4, y: 4)
                        }
                    }
            }
            .buttonStyle(.plain)
            .alert("Sign out?", isPresented: $showLogoutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive) {
                    Task { @MainActor in
                        try? Auth.auth().signOut()
                        authTick += 1
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
        .id(authTick)
    }
}
