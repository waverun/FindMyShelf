import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()

    // נשמור את שם החנות הנבחרת (כרגע רק בזיכרון – בשלב הבא אפשר גם @AppStorage)
    @State private var selectedStoreName: String?
    @State private var selectedStoreDistance: Double?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {

                Text("FindMyShelf")
                    .font(.largeTitle.bold())

                Text("שלב 1–2: מיקום + בחירת חנות")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Group {
                    if let status = locationManager.authorizationStatus {
                        Text("סטטוס הרשאת מיקום: \(describe(status))")
                    } else {
                        Text("סטטוס הרשאת מיקום: לא ידוע עדיין")
                    }
                }
                .font(.subheadline)

                // הצגת המיקום
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

                // הצגת החנות הנבחרת
                if let name = selectedStoreName {
                    VStack(spacing: 4) {
                        Text("החנות שנבחרה:")
                            .font(.headline)
                        Text(name)
                        if let d = selectedStoreDistance {
                            Text(String(format: "כ-%0.0f מטרים כשהיא נבחרה", d))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.thinMaterial)
                    .cornerRadius(12)
                }

                if let loc = locationManager.currentLocation {
                    NavigationLink {
                        NearbyStoresView(locationManager: locationManager) { store in
                            // פה אנחנו מעדכנים את הבחירה
                            selectedStoreName = store.name
                            selectedStoreDistance = store.distance
                        }
                    } label: {
                        Text("מצא חנויות קרובות ובחר \"זו החנות שלי\"")
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("כדי לחפש חנויות קרובות, צריך קודם מיקום.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let msg = locationManager.errorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

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
