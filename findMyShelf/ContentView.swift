import SwiftUI
import CoreLocation
import SwiftData

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()

    @Environment(\.modelContext) private var context
    @Query(sort: \Store.createdAt) private var stores: [Store]

    // מזהה החנות שנבחרה – נשמר ב-UserDefaults
    @AppStorage("selectedStoreId") private var selectedStoreId: String?

    // חנות נבחרת בפועל (אם קיימת ב-DB)
    private var selectedStore: Store? {
        guard let idString = selectedStoreId,
              let uuid = UUID(uuidString: idString) else { return nil }
        return stores.first(where: { $0.id == uuid })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {

                Text("FindMyShelf")
                    .font(.largeTitle.bold())

                Text("שלב 1–2: מיקום + בחירת חנות")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // סטטוס הרשאה
                Group {
                    if let status = locationManager.authorizationStatus {
                        Text("סטטוס הרשאת מיקום: \(describe(status))")
                    } else {
                        Text("סטטוס הרשאת מיקום: לא ידוע עדיין")
                    }
                }
                .font(.subheadline)

                // מיקום נוכחי
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

                if let store = selectedStore {
                    VStack(spacing: 4) {
                        Text("החנות שנבחרה:")
                            .font(.headline)
                        Text(store.name)
                        if let lat = store.latitude, let lon = store.longitude {
                            Text(String(format: "lat: %.5f, lon: %.5f", lat, lon))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.thinMaterial)
                    .cornerRadius(12)

                    NavigationLink {
                        AisleListView(store: store)
                    } label: {
                        Text("המשך למיפוי השורות")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        ProductSearchView(store: store)
                    } label: {
                        Text("חפש מוצר לפי שורות")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                } else {
                    Text("עדיין לא נבחרה חנות.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // חנות נבחרת מה-DB
//                if let store = selectedStore {
//                    VStack(spacing: 4) {
//                        Text("החנות שנבחרה:")
//                            .font(.headline)
//                        Text(store.name)
//                        if let lat = store.latitude, let lon = store.longitude {
//                            Text(String(format: "lat: %.5f, lon: %.5f", lat, lon))
//                                .font(.footnote)
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//                    .padding()
//                    .background(.thinMaterial)
//                    .cornerRadius(12)
//                } else {
                    Text("עדיין לא נבחרה חנות.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // מעבר למסך חיפוש חנויות קרובות
                if locationManager.currentLocation != nil {
                    NavigationLink {
                        NearbyStoresView(locationManager: locationManager) { nearby in
                            handleStoreChosen(nearby)
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
//    }

    // MARK: - Logic

    /// מה עושים כשהמשתמש בוחר "זו החנות שלי" במסך החנויות הקרובות
    private func handleStoreChosen(_ nearby: NearbyStore) {
        // אופציה 1: לבדוק אם כבר יש חנות עם אותו שם וקואורדינטות דומות
        if let existing = stores.first(where: { s in
            s.name == nearby.name &&
            abs((s.latitude ?? 0) - nearby.coordinate.latitude) < 0.0005 &&
            abs((s.longitude ?? 0) - nearby.coordinate.longitude) < 0.0005
        }) {
            // משתמש בחנות קיימת
            selectedStoreId = existing.id.uuidString
        } else {
            // יוצר חנות חדשה
            let newStore = Store(
                name: nearby.name,
                latitude: nearby.coordinate.latitude,
                longitude: nearby.coordinate.longitude
            )
            context.insert(newStore)
            do {
                try context.save()
                selectedStoreId = newStore.id.uuidString
            } catch {
                print("Failed to save store:", error)
            }
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

