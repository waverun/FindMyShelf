import SwiftUI
import CoreLocation
import MapKit

struct NearbyStoresView: View {
    @ObservedObject var locationManager: LocationManager
    @StateObject private var finder = StoreFinder()
    @Environment(\.dismiss) private var dismiss

    /// מה עושים כשמשתמש בחר "זו החנות שלי"
    let onStoreChosen: (NearbyStore) -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let loc = locationManager.currentLocation {
                Text("המיקום הנוכחי שלך:\nlat: \(loc.coordinate.latitude), lon: \(loc.coordinate.longitude)")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)

                Button {
                    finder.searchNearby(from: loc)
                } label: {
                    if finder.isSearching {
                        ProgressView()
                    } else {
                        Text("חפש חנויות קרובות")
                    }
                }
                .buttonStyle(.borderedProminent)

                if let guess = finder.guessCurrentStore() {
                    VStack(spacing: 4) {
                        Text("נראה שאתה נמצא ב:")
                            .font(.subheadline)
                        Text(guess.name)
                            .font(.headline)
                        if let d = guess.distance {
                            Text(String(format: "כ-%0.0f מטרים ממך", d))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button("אשר שזו החנות שלי") {
                            onStoreChosen(guess)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(.thinMaterial)
                    .cornerRadius(12)
                }

                List(finder.results) { store in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(store.name)
                                .font(.headline)
                            Spacer()
                            if let d = store.distance {
                                Text(String(format: "%0.0f מ'", d))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button("זו החנות שלי") {
                            onStoreChosen(store)
                            dismiss()
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("אין עדיין מיקום.\nחזור למסך הראשי ואשר הרשאת מיקום.")
                    .multilineTextAlignment(.center)
                    .padding()
            }

            if let err = finder.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("חנויות קרובות")
    }
}
