import Foundation
import FirebaseAuth
import FirebaseFirestore
import MapKit
import SwiftData
import CryptoKit

@MainActor
final class FirebaseService: ObservableObject {

    private let db = Firestore.firestore()
    private var aislesListener: ListenerRegistration?
    private var productsListener: ListenerRegistration?

    // MARK: - Reports Admin - Fetch content edited by a user

    func fetchStoresEditedByUser(userId: String, limit: Int = 50) async throws -> [EditedStoreRow] {
        let snap = try await db.collection("stores")
            .whereField("updatedByUserId", isEqualTo: userId)
            .limit(to: limit)
            .getDocuments()

        return snap.documents.map { doc in
            let name = (doc.get("name") as? String) ?? ""
            let addressCombined = doc.get("address") as? String  // you currently store combined address
            return EditedStoreRow(
                storeRemoteId: doc.documentID,
                name: name,
                address: addressCombined
            )
        }
    }

    /// Requires that each aisle doc contains storeRemoteId (or storeId) field.
    /// If you DON'T have it yet, see note below.
    func fetchAislesEditedByUser(userId: String, limit: Int = 100) async throws -> [EditedAisleRow] {
        let snap = try await db.collectionGroup("aisles")
            .whereField("updatedByUserId", isEqualTo: userId)
            .limit(to: limit)
            .getDocuments()

        return snap.documents.map { doc in
            let name = (doc.get("nameOrNumber") as? String) ?? ""
            let keywords = (doc.get("keywords") as? [String]) ?? []
            let storeRemoteId = doc.get("storeRemoteId") as? String  // IMPORTANT (see note)

            return EditedAisleRow(
                aisleRemoteId: doc.documentID,
                storeRemoteId: storeRemoteId,
                nameOrNumber: name,
                keywords: keywords
            )
        }
    }

    // Small DTOs for UI
    struct EditedStoreRow: Identifiable {
        var id: String { storeRemoteId }
        let storeRemoteId: String
        let name: String
        let address: String?
    }

    struct EditedAisleRow: Identifiable {
        var id: String { "\(storeRemoteId ?? "unknown")|\(aisleRemoteId)" }
        let aisleRemoteId: String
        let storeRemoteId: String? // may be nil if not stored
        let nameOrNumber: String
        let keywords: [String]
    }
    // MARK: - STORE

    // MARK: - Reports Admin (Debug)

    func startReportsListener(
        onChange: @escaping ([ReportedUserReport]) -> Void
    ) -> ListenerRegistration {
        // Order newest first; we split new/handled client-side by handledAt
        return db.collection("reportedUsers")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snap, err in
                if let err {
                    print("❌ Reports listener error:", err)
                    onChange([])
                    return
                }
                guard let snap else {
                    onChange([])
                    return
                }

                let items: [ReportedUserReport] = snap.documents.map { doc in
                    ReportedUserReport.from(doc: doc)
                }
                onChange(items)
            }
    }

    func deleteReport(reportId: String) async throws {
        try await db.collection("reportedUsers")
            .document(reportId)
            .delete()
    }

    func markReportHandled(reportId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }

        let data: [String: Any] = [
            "handledAt": FieldValue.serverTimestamp(),
            "handledByUserId": uid
        ]

        try await db.collection("reportedUsers")
            .document(reportId)
            .setData(data, merge: true)
    }
    // MARK: - Reporting + Attribution helpers

    func fetchStoreAttribution(storeRemoteId: String) async throws -> (createdBy: String?, updatedBy: String?) {
        let doc = try await db.collection("stores").document(storeRemoteId).getDocument()
        let createdBy = doc.get("createdByUserId") as? String
        let updatedBy = doc.get("updatedByUserId") as? String
        return (createdBy, updatedBy)
    }

    func submitUserReport(
        reportedUserId: String,
        reporterUserId: String,
        reason: String,
        details: String,
        storeRemoteId: String?,
        context: String
    ) async throws {

        var data: [String: Any] = [
            "reportedUserId": reportedUserId,
            "reporterUserId": reporterUserId,
            "reason": reason,                         // "no_reason_selected" if none
            "details": details,                       // may be empty if reason chosen
            "context": context,                       // e.g. "store_last_editor"
            "createdAt": FieldValue.serverTimestamp()
        ]

        if let storeRemoteId {
            data["storeRemoteId"] = storeRemoteId
        }

        _ = try await db.collection("reportedUsers").addDocument(data: data)
    }

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

    func startProductsListener(
        storeRemoteId: String,
        localStoreId: UUID,
        context: ModelContext
    ) {
        stopProductsListener()

        productsListener = db.collection("stores")
            .document(storeRemoteId)
            .collection("products")
            .addSnapshotListener { snap, err in
                if let err {
                    print("Firestore products listener error:", err)
                    return
                }
                guard let snap else { return }

                Task { @MainActor in
                    self.applyProductsSnapshot(
                        snap,
                        localStoreId: localStoreId,
                        context: context
                    )
                }
            }
    }

    private func applyProductsSnapshot(
        _ snap: QuerySnapshot,
        localStoreId: UUID,
        context: ModelContext
    ) {
        // local products for this store
        let desc = FetchDescriptor<ProductItem>()
        let allLocal = (try? context.fetch(desc)) ?? []
        let localForStore = allLocal.filter { $0.storeId == localStoreId }

        // build aisleRemoteId -> localAisleUUID map (so we can set aisleId)
        let ad = FetchDescriptor<Aisle>()
        let allAisles = (try? context.fetch(ad)) ?? []
        let aislesForStore = allAisles.filter { $0.storeId == localStoreId }
        var aisleLocalIdByRemoteId: [String: UUID] = [:]
        for a in aislesForStore {
            if let rid = a.remoteId {
                aisleLocalIdByRemoteId[rid] = a.id
            }
        }

        var localByRemoteId: [String: ProductItem] = [:]
        for p in localForStore {
            if let rid = p.remoteId { localByRemoteId[rid] = p }
        }

        var seen = Set<String>()

        for doc in snap.documents {
            let rid = doc.documentID
            seen.insert(rid)

            let name = (doc.get("name") as? String) ?? ""
            let barcode = doc.get("barcode") as? String
            let aisleRid = doc.get("aisleRemoteId") as? String

            let localAisleId = aisleRid.flatMap { aisleLocalIdByRemoteId[$0] }

            if let local = localByRemoteId[rid] {
                local.name = name
                local.barcode = barcode
                local.aisleRemoteId = aisleRid
                local.aisleId = localAisleId
                local.updatedAt = .now
            } else {
                // try merge with offline local product (remoteId == nil) by name
                if let match = localForStore.first(where: { $0.remoteId == nil && norm($0.name) == norm(name) }) {
                    match.remoteId = rid
                    match.name = name
                    match.barcode = barcode
                    match.aisleRemoteId = aisleRid
                    match.aisleId = localAisleId
                    match.updatedAt = .now
                } else {
                    let p = ProductItem(name: name, storeId: localStoreId, aisleId: localAisleId, barcode: barcode)
                    p.remoteId = rid
                    p.aisleRemoteId = aisleRid
                    p.updatedAt = .now
                    context.insert(p)
                }
            }
        }

        // delete local products that came from cloud but were removed
        for p in localForStore {
            if let rid = p.remoteId, !seen.contains(rid) {
                context.delete(p)
            }
        }

        try? context.save()
    }

    func upsertProduct(
        storeRemoteId: String,
        product: ProductItem,
        aisleRemoteId: String?
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }

        // deterministic doc id prevents duplicates:
        let docId = Self.productDocId(normalizedName: Self.normalize(product.name))

        var data: [String: Any] = [
            "name": product.name,
            "normalizedName": Self.normalize(product.name),
            "barcode": product.barcode as Any,
            "aisleRemoteId": aisleRemoteId as Any,
            "storeRemoteId": storeRemoteId,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedByUserId": uid
        ]

        // If this is first time, also set created fields (merge keeps them if already exist)
        data["createdAt"] = FieldValue.serverTimestamp()
        data["createdByUserId"] = uid

        try await db.collection("stores")
            .document(storeRemoteId)
            .collection("products")
            .document(docId)
            .setData(data, merge: true)

        // update local mapping
        product.remoteId = docId
        product.aisleRemoteId = aisleRemoteId
        product.updatedAt = .now
    }

//    import CryptoKit
    static func productDocId(normalizedName: String) -> String {
        let data = Data(normalizedName.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    func stopProductsListener() {
        productsListener?.remove()
        productsListener = nil
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
            "updatedByUserId": uid,
            "storeRemoteId": storeRemoteId
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
            "updatedByUserId": uid,
            "storeRemoteId": storeRemoteId
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

struct ReportedUserReport: Identifiable {
    let id: String

    let reportedUserId: String
    let reporterUserId: String
    let reason: String
    let details: String
    let storeRemoteId: String?
    let context: String?

    let createdAt: Date?
    let handledAt: Date?
    let handledByUserId: String?

    var isHandled: Bool { handledAt != nil }

    static func from(doc: QueryDocumentSnapshot) -> ReportedUserReport {
        let createdTs = doc.get("createdAt") as? Timestamp
        let handledTs = doc.get("handledAt") as? Timestamp

        return ReportedUserReport(
            id: doc.documentID,
            reportedUserId: (doc.get("reportedUserId") as? String) ?? "",
            reporterUserId: (doc.get("reporterUserId") as? String) ?? "",
            reason: (doc.get("reason") as? String) ?? "no_reason_selected",
            details: (doc.get("details") as? String) ?? "",
            storeRemoteId: doc.get("storeRemoteId") as? String,
            context: doc.get("context") as? String,
            createdAt: createdTs?.dateValue(),
            handledAt: handledTs?.dateValue(),
            handledByUserId: doc.get("handledByUserId") as? String
        )
    }
}
