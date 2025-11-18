import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {

                Text("FindMyShelf")
                    .font(.largeTitle.bold())

                Text("שלב 1: בדיקת מיקום")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // סטטוס הרשאה
                Group {
                    if let status = locationManager.authorizationStatus {
                        Text("סטטוס הרשאה: \(describe(status))")
                    } else {
                        Text("סטטוס הרשאה: לא ידוע עדיין")
                    }
                }
                .font(.subheadline)

                // הצגת המיקום הנוכחי אם קיים
                Group {
                    if let loc = locationManager.currentLocation {
                        VStack(spacing: 4) {
                            Text("המיקום שלך כרגע:")
                                .font(.headline)
                            Text(String(format: "Latitude: %.5f", loc.coordinate.latitude))
                            Text(String(format: "Longitude: %.5f", loc.coordinate.longitude))
                        }
                    } else {
                        Text("עוד אין מיקום. לחץ על \"אפשר מיקום\".")
                            .multilineTextAlignment(.center)
                    }
                }
                .font(.body)

                // הודעת שגיאה אם יש
                if let msg = locationManager.errorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // כפתורים
                VStack(spacing: 12) {
                    Button("אפשר מיקום") {
                        locationManager.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("רענן מיקום") {
                        locationManager.startUpdating()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("מסך ראשי")
        }
    }

    private func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
            case .notDetermined: return "לא הוחלט עדיין"
            case .restricted:    return "מוגבל"
            case .denied:        return "נשללה"
            case .authorizedAlways: return "מאושרת תמיד"
            case .authorizedWhenInUse: return "מאושרת בשימוש באפליקציה"
            @unknown default:    return "לא מוכר"
        }
    }
}
