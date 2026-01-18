import Foundation
import SwiftData
// בדיקת פוש
@Model
final class Aisle {
    var id: UUID
    var storeId: UUID      // מזהה החנות
    var nameOrNumber: String
    var keywords: [String]
    var createdAt: Date

    init(nameOrNumber: String,
         storeId: UUID,
         keywords: [String] = []) {
        self.id = UUID()
        self.storeId = storeId
        self.nameOrNumber = nameOrNumber
        self.keywords = keywords
        self.createdAt = .now
    }
}
