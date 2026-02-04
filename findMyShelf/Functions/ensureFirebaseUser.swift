import FirebaseAuth

@MainActor
func ensureFirebaseUser() async throws -> User {
    if let user = Auth.auth().currentUser {
        return user
    }

    return try await withCheckedThrowingContinuation { cont in
        Auth.auth().signInAnonymously { result, error in
            if let error = error {
                cont.resume(throwing: error)
                return
            }
            if let user = result?.user {
                cont.resume(returning: user)
            } else {
                cont.resume(throwing: NSError(domain: "Auth", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "signInAnonymously returned nil user"
                ]))
            }
        }
    }
}//
//  ensureFirebaseUser.swift
//  findMyShelf
//
//  Created by shay moreno on 04/02/2026.
//

import Foundation
