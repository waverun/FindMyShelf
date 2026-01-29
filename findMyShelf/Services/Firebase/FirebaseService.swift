import Foundation
import FirebaseAuth
import FirebaseFirestore
import MapKit
import SwiftData

@MainActor
final class FirebaseService: ObservableObject {

    private let db = Firestore.firestore()
    private var aislesListener: ListenerRegistration?

    // MARK: - STORE

//    func updateStore(
//        storeRemoteId: String,
//        name: String,
//        address: String?,
//        city: String?
//    ) async throws {
//        var data: [String: Any] = [
//            "name": name,
//            "updatedAt": FieldValue.serverTimestamp()
//        ]
//
//        // store address in ONE field or two—pick what you use in Firestore:
//        let combined = [address, city]
//            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
//            .filter { !$0.isEmpty }
//            .joined(separator: ", ")
//
//        data["address"] = combined.isEmpty ? NSNull() : combined
//
//        try await db.collection("stores")
//            .document(storeRemoteId)
//            .setData(data, merge: true)
//    }

    func updateStore(
        storeRemoteId: String,
        name: String,
        address: String?,
        city: String?
    ) async throws {

        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }

        var data: [String: Any] = [
            "name": name,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedByUserId": uid
        ]

        let combined = [address, city]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        data["address"] = combined.isEmpty ? NSNull() : combined

        try await db.collection("stores")
            .document(storeRemoteId)
            .setData(data, merge: true)
    }

    /// Fetch existing store by geoCell + name similarity, or create new one
    func fetchOrCreateStore(
        name: String,
        address: String?,
        latitude: Double?,
        longitude: Double?
    ) async throws -> String {

        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }

        let normalizedName = Self.normalize(name)

        var geoCell: String?
        if let lat = latitude, let lng = longitude {
            geoCell = Self.geoCell(lat: lat, lng: lng)
        }

        if let geoCell {
            let snap = try await db.collection("stores")
                .whereField("geoCell", isEqualTo: geoCell)
                .limit(to: 20)
                .getDocuments()

            if let match = snap.documents.first(where: { doc in
                let stored = (doc.get("normalizedName") as? String) ?? ""
                return stored == normalizedName
            }) {
                return match.documentID
            }
        }

        var data: [String: Any] = [
            "name": name,
            "normalizedName": normalizedName,
            "address": address as Any,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "createdByUserId": uid,
            "updatedByUserId": uid
        ]

//        var data: [String: Any] = [
//            "name": name,
//            "normalizedName": normalizedName,
//            "address": address as Any,
//            "createdAt": FieldValue.serverTimestamp(),
//            "updatedAt": FieldValue.serverTimestamp()
//        ]

        if let lat = latitude, let lng = longitude {
            data["geo"] = [
                "lat": lat,
                "lng": lng
            ]
            data["geoCell"] = geoCell as Any
        }

        let ref = try await db.collection("stores").addDocument(data: data)
        return ref.documentID
    }

    // MARK: - AISLES LISTENER

    func startAislesListener(
        storeRemoteId: String,
        localStoreId: UUID,
        context: ModelContext
    ) {
        stopAislesListener()

        aislesListener = db.collection("stores")
            .document(storeRemoteId)
            .collection("aisles")
            .addSnapshotListener { snap, err in
                if let err {
                    print("Firestore listener error:", err)
                    return
                }
                guard let snap else { return }

                Task { @MainActor in
                    self.applyAislesSnapshot(
                        snap,
                        localStoreId: localStoreId,
                        context: context
                    )
                }
            }
    }

    func stopAislesListener() {
        aislesListener?.remove()
        aislesListener = nil
    }

    private func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func applyAislesSnapshot(
        _ snap: QuerySnapshot,
        localStoreId: UUID,
        context: ModelContext
    ) {

        let descriptor = FetchDescriptor<Aisle>()
        let allLocal = (try? context.fetch(descriptor)) ?? []
        let localForStore = allLocal.filter { $0.storeId == localStoreId }

        var localByRemoteId: [String: Aisle] = [:]
        for a in localForStore {
            if let rid = a.remoteId {
                localByRemoteId[rid] = a
            }
        }

        var seen = Set<String>()

        for doc in snap.documents {
            let rid = doc.documentID
            seen.insert(rid)

            let name = (doc.get("nameOrNumber") as? String) ?? ""
            let keywords = (doc.get("keywords") as? [String]) ?? []

            if let local = localByRemoteId[rid] {
                // ✅ already linked by remoteId -> normal update
                local.nameOrNumber = name
                local.keywords = keywords
                local.updatedAt = .now

            } else {
                // ✅ NEW: try merge with local aisle created offline (remoteId == nil)
                if let match = localForStore.first(where: { $0.remoteId == nil && norm($0.nameOrNumber) == norm(name) }) {

                    match.remoteId = rid
                    match.keywords = keywords
                    match.updatedAt = .now
                } else {
                    // ✅ truly new -> create locally
                    let newAisle = Aisle(
                        nameOrNumber: name,
                        storeId: localStoreId,
                        keywords: keywords
                    )
                    newAisle.remoteId = rid
                    newAisle.updatedAt = .now
                    context.insert(newAisle)
                }
            }
        }

        for local in localForStore {
            if let rid = local.remoteId, !seen.contains(rid) {
                context.delete(local)
            }
        }

        try? context.save()
    }

    // MARK: - AISLE WRITES

//    func createAisle(
//        storeRemoteId: String,
//        aisle: Aisle
//    ) async throws -> String {
//
//        let data: [String: Any] = [
//            "nameOrNumber": aisle.nameOrNumber,
//            "keywords": aisle.keywords,
//            "createdAt": FieldValue.serverTimestamp(),
//            "updatedAt": FieldValue.serverTimestamp()
//        ]
//
//        let ref = try await db.collection("stores")
//            .document(storeRemoteId)
//            .collection("aisles")
//            .addDocument(data: data)
//
//        return ref.documentID
//    }

    func createAisle(
        storeRemoteId: String,
        aisle: Aisle
    ) async throws -> String {

        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }

        let data: [String: Any] = [
            "nameOrNumber": aisle.nameOrNumber,
            "keywords": aisle.keywords,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "createdByUserId": uid,
            "updatedByUserId": uid
        ]

        let ref = try await db.collection("stores")
            .document(storeRemoteId)
            .collection("aisles")
            .addDocument(data: data)

        return ref.documentID
    }

    func updateAisle(
        storeRemoteId: String,
        aisle: Aisle
    ) async throws {

        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }

        guard let rid = aisle.remoteId else { return }

        let data: [String: Any] = [
            "nameOrNumber": aisle.nameOrNumber,
            "keywords": aisle.keywords,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedByUserId": uid
        ]

        try await db.collection("stores")
            .document(storeRemoteId)
            .collection("aisles")
            .document(rid)
            .setData(data, merge: true)
    }
    
//    func updateAisle(
//        storeRemoteId: String,
//        aisle: Aisle
//    ) async throws {
//
//        guard let rid = aisle.remoteId else { return }
//
//        let data: [String: Any] = [
//            "nameOrNumber": aisle.nameOrNumber,
//            "keywords": aisle.keywords,
//            "updatedAt": FieldValue.serverTimestamp()
//        ]
//
//        try await db.collection("stores")
//            .document(storeRemoteId)
//            .collection("aisles")
//            .document(rid)
//            .setData(data, merge: true)
//    }

    func deleteAisle(
        storeRemoteId: String,
        aisleRemoteId: String
    ) async throws {

        try await db.collection("stores")
            .document(storeRemoteId)
            .collection("aisles")
            .document(aisleRemoteId)
            .delete()
    }

    // MARK: - HELPERS

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }

    static func geoCell(lat: Double, lng: Double) -> String {
        let latR = (lat * 1000).rounded() / 1000
        let lngR = (lng * 1000).rounded() / 1000
        return "\(latR)|\(lngR)"
    }

    @MainActor
    func syncCreatedAisleToFirebase(
        _ aisle: Aisle,
        store: Store,
        context: ModelContext,
        onError: @escaping (String) -> Void
    ) async {
        // already synced
        if aisle.remoteId != nil { return }

        // make sure store has remoteId (ContentView already calls ensureStoreRemoteId,
        // but we keep it safe)
        guard let storeRemoteId = store.remoteId else {
            onError("Store is not synced to Firebase")
            return
        }

        do {
            let rid = try await createAisle(storeRemoteId: storeRemoteId, aisle: aisle)
            aisle.remoteId = rid
            aisle.updatedAt = Date()
            try? context.save()
            print("✅ Aisle synced to Firebase. aisleRemoteId:", rid)
        } catch {
            print("❌ Failed to create aisle in Firebase:", error)
            onError("Failed to sync aisle to Firebase")
        }
    }

    func deleteStore(storeRemoteId: String) async throws {
        let storeRef = db.collection("stores").document(storeRemoteId)

        // 🔥 delete all aisles first
        let aislesSnap = try await storeRef.collection("aisles").getDocuments()
        for doc in aislesSnap.documents {
            try await doc.reference.delete()
        }

        // 🔥 delete store itself
        try await storeRef.delete()
    }
}
