import Foundation
import FirebaseAuth

func ensureFirebaseUser(timeoutSeconds: Double = 8) async throws -> User {
    if let user = Auth.auth().currentUser { return user }

    return try await withThrowingTaskGroup(of: User.self) { group in
        group.addTask {
            let result = try await Auth.auth().signInAnonymously()
            return result.user
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            throw NSError(domain: "Auth", code: -1001, userInfo: [
                NSLocalizedDescriptionKey: "Anonymous sign-in timed out after \(timeoutSeconds)s"
            ])
        }

        let user = try await group.next()!
        group.cancelAll()
        return user
    }
}

//import FirebaseAuth
//
//@MainActor
//func ensureFirebaseUser() async throws -> User {
//    if let user = Auth.auth().currentUser {
//        return user
//    }
//
//    return try await withCheckedThrowingContinuation { cont in
//        Auth.auth().signInAnonymously { result, error in
//            if let error = error {
//                cont.resume(throwing: error)
//                return
//            }
//            if let user = result?.user {
//                cont.resume(returning: user)
//            } else {
//                cont.resume(throwing: NSError(domain: "Auth", code: -1, userInfo: [
//                    NSLocalizedDescriptionKey: "signInAnonymously returned nil user"
//                ]))
//            }
//        }
//    }
//}//
////  ensureFirebaseUser.swift
////  findMyShelf
////
////  Created by shay moreno on 04/02/2026.
////
//
//import Foundation
