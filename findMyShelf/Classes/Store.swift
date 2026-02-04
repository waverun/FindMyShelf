import Foundation
import SwiftData
@Model
final class Store {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var latitude: Double?
    var longitude: Double?
    var addressLine: String?
    var city: String?

    // ✅ Firebase
    var remoteId: String?   // <-- add this

    @Relationship(deleteRule: .cascade) var aisles: [Aisle] = []
    @Relationship(deleteRule: .cascade) var products: [ProductItem] = []

    init(name: String,
         latitude: Double? = nil,
         longitude: Double? = nil,
         addressLine: String? = nil,
         city: String? = nil) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.latitude = latitude
        self.longitude = longitude
        self.addressLine = addressLine
        self.city = city
        self.remoteId = nil     // <-- add this (optional but nice)
    }
}
