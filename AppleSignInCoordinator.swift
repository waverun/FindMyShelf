import AuthenticationServices
import FirebaseAuth
import UIKit

final class AppleSignInCoordinator: NSObject {
    func start() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityToken = appleIDCredential.identityToken,
            let tokenString = String(data: identityToken, encoding: .utf8)
        else { return }

        let credential = OAuthProvider.appleCredential(
            withIDToken: tokenString,
            rawNonce: nil,
            fullName: appleIDCredential.fullName
        )

        Task {
            try await Auth.auth().signIn(with: credential)
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        // Optional: handle cancel/error
        // print("Apple Sign-In error:", error)
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {

    @MainActor @objc
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
            let window = scene.windows.first
        else {
            return ASPresentationAnchor()
        }
        return window
    }
}
