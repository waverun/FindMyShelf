import Foundation
import CoreLocation

final class LocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus?
    @Published var errorMessage: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// בקשת הרשאה מהמשתמש
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// התחלת עדכון מיקום
    func startUpdating() {
        manager.startUpdatingLocation()
    }

    /// עצירת עדכון מיקום (לא חובה בשלב הזה, אבל נחמד שיהיה)
    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                errorMessage = nil
                startUpdating()
            case .denied, .restricted:
                errorMessage = "אין הרשאת מיקום. אפשר לשנות זאת בהגדרות."
            case .notDetermined:
                errorMessage = nil
            @unknown default:
                errorMessage = "סטטוס הרשאה לא מוכר."
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        errorMessage = "שגיאה בקבלת מיקום: \(error.localizedDescription)"
    }
}
