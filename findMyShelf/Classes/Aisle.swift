import Foundation
import SwiftData


@Model
final class Aisle {
    var id: UUID
    var storeId: UUID
    var remoteId: String?
    var nameOrNumber: String
    var keywords: [String]
    var createdAt: Date
    var updatedAt: Date       // ✅ add

    init(nameOrNumber: String,
         storeId: UUID,
         keywords: [String] = []) {

        self.id = UUID()
        self.storeId = storeId
        self.remoteId = nil
        self.nameOrNumber = nameOrNumber
        self.keywords = keywords
        self.createdAt = .now
        self.updatedAt = .now   // ✅ add
    }
}
