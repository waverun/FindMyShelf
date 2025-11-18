import Foundation
import SwiftData

@Model
final class Store {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var latitude: Double?
    var longitude: Double?

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
