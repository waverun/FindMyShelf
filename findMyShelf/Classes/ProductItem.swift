import Foundation
import SwiftData

@Model
final class ProductItem {
    var id: UUID
    var storeId: UUID
    var aisleId: UUID?          // local link

    // ✅ Firebase mapping
    var remoteId: String?       // Firestore doc id
    var aisleRemoteId: String?  // Firestore aisle doc id (to remap aisleId locally)

    var name: String
    var barcode: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        storeId: UUID,
        aisleId: UUID? = nil,
        barcode: String? = nil
    ) {
        self.id = UUID()
        self.storeId = storeId
        self.aisleId = aisleId
        self.remoteId = nil
        self.aisleRemoteId = nil
        self.name = name
        self.barcode = barcode
        self.createdAt = .now
        self.updatedAt = .now
    }
}

//import Foundation
//import SwiftData
//
//@Model
//final class ProductItem {
//    var id: UUID
//    var storeId: UUID       // החנות
//    var aisleId: UUID?      // השורה (אופציונלי)
//
//    var name: String        // שם המוצר
//    var barcode: String?    // לא חובה עכשיו, אפשר להשאיר ריק
//    var createdAt: Date
//
//    init(name: String,
//         storeId: UUID,
//         aisleId: UUID? = nil,
//         barcode: String? = nil) {
//        self.id = UUID()
//        self.storeId = storeId
//        self.aisleId = aisleId
//        self.name = name
//        self.barcode = barcode
//        self.createdAt = .now
//    }
//}
