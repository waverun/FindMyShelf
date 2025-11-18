import Foundation
import SwiftData

@Model
final class ProductItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var barcode: String?
    var createdAt: Date

    // קשרים
    var store: Store?
    var aisle: Aisle?

    init(name: String,
         barcode: String? = nil,
         store: Store? = nil,
         aisle: Aisle? = nil) {
        self.id = UUID()
        self.name = name
        self.barcode = barcode
        self.createdAt = .now
        self.store = store
        self.aisle = aisle
    }
}
