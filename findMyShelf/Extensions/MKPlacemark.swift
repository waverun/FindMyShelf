import MapKit

extension MKPlacemark {
    var shortAddressLine: String? {
        var parts: [String] = []
        if let thoroughfare { parts.append(thoroughfare) }
        if let subThoroughfare { parts.append(subThoroughfare) }
        if let locality { parts.append(locality) }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " ")
    }
}
