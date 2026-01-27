import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import GoogleSignInSwift

func signInWithGoogle() async throws {
    guard let clientID = FirebaseApp.app()?.options.clientID else {
        return
    }

    // UIKit חייב לרוץ על MainActor
    let rootVC: UIViewController? = await MainActor.run {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
            let window = scene.windows.first
        else { return nil }

        return window.rootViewController
    }

    guard let rootVC else { return }

    let config = GIDConfiguration(clientID: clientID)
    GIDSignIn.sharedInstance.configuration = config

    let result = try await GIDSignIn.sharedInstance.signIn(
        withPresenting: rootVC
    )

    guard let idToken = result.user.idToken?.tokenString else {
        return
    }

    let credential = GoogleAuthProvider.credential(
        withIDToken: idToken,
        accessToken: result.user.accessToken.tokenString
    )

    try await Auth.auth().signIn(with: credential)
}
