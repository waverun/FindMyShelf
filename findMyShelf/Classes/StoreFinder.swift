import Foundation
import MapKit
import CoreLocation

/// מודל פשוט של חנות שנמצאה קרוב אלינו
/// struct NearbyStore: Identifiable {
struct NearbyStore: Identifiable {
    let id = UUID()
    let name: String
    let addressLine: String?
    let city: String?
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance?
    let rawItem: MKMapItem
}

//struct NearbyStore: Identifiable {
//    let id = UUID()
//    let name: String
//    let coordinate: CLLocationCoordinate2D
//    let distance: CLLocationDistance?
//    let rawItem: MKMapItem
//}

/// מחלקה שמבצעת חיפוש חנויות ליד מיקום נתון
final class StoreFinder: ObservableObject {
    @Published var results: [NearbyStore] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?

    /// חיפוש סופרים/חנויות מזון בקרבת המיקום
    func searchNearby(from location: CLLocation) {
        isSearching = true
        errorMessage = nil
        results = []

        let request = MKLocalSearch.Request()
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 1500,   // רדיוס בערך 1.5 ק"מ
            longitudinalMeters: 1500
        )

        // אפשר לשחק עם השאילתה: כולל עברית/אנגלית
        request.naturalLanguageQuery = "supermarket"

        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            DispatchQueue.main.async {
                self?.isSearching = false
            }

            guard let self = self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.errorMessage = "שגיאה בחיפוש: \(error.localizedDescription)"
                }
                return
            }

            guard let response = response else {
                DispatchQueue.main.async {
                    self.errorMessage = "לא נמצאו תוצאות."
                }
                return
            }

            let origin = location
            let mapped: [NearbyStore] = response.mapItems.map { item in
                let dist = item.placemark.location?.distance(from: origin)
                let pm = item.placemark
                let addr = (pm as MKPlacemark).shortAddressLine
                let city = pm.locality
                return NearbyStore(
                    name: item.name ?? "חנות ללא שם",
                    addressLine: addr,
                    city: city,
                    coordinate: pm.coordinate,
                    distance: dist,
                    rawItem: item
                )

//                return NearbyStore(
//                    name: item.name ?? "חנות ללא שם",
//                    coordinate: item.placemark.coordinate,
//                    distance: dist,
//                    rawItem: item
//                )
            }
                .sorted {
                    ($0.distance ?? .greatestFiniteMagnitude) <
                        ($1.distance ?? .greatestFiniteMagnitude)
                }

            DispatchQueue.main.async {
                self.results = mapped
                if mapped.isEmpty {
                    self.errorMessage = "לא נמצאו חנויות קרובות."
                }
            }
        }
    }

    /// ניחוש איזו חנות היא "הסופר שאתה עומד בו" – לפי המרחק הכי קטן
    func guessCurrentStore() -> NearbyStore? {
        guard let first = results.first,
              let dist = first.distance else { return nil }

        // סף גס – אם החנות קרובה פחות מ-80 מטר, כנראה זה הסניף
        if dist < 80 {
            return first
        }
        return nil
    }
}
