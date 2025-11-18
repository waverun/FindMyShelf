import Foundation
import SwiftData

@Model
final class Store {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var latitude: Double?
    var longitude: Double?

    // קשרים לשורות ולמוצרים
    @Relationship(deleteRule: .cascade) var aisles: [Aisle] = []
    @Relationship(deleteRule: .cascade) var products: [ProductItem] = []

    init(name: String,
         latitude: Double? = nil,
         longitude: Double? = nil) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.latitude = latitude
        self.longitude = longitude
    }
}
