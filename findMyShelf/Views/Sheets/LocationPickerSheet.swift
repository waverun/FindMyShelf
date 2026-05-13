import SwiftUI
import MapKit
import CoreLocation

struct LocationPickerSheet: View {
    let initialCoordinate: CLLocationCoordinate2D?
    let onCancel: () -> Void
    let onConfirm: (CLLocationCoordinate2D) -> Void

    @State private var cameraPosition: MapCameraPosition
    @State private var selectedCoordinate: CLLocationCoordinate2D?

    init(
        initialCoordinate: CLLocationCoordinate2D?,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        self.initialCoordinate = initialCoordinate
        self.onCancel = onCancel
        self.onConfirm = onConfirm

        let start = initialCoordinate ?? CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818)
        let startRegion = MKCoordinateRegion(
            center: start,
            latitudinalMeters: 2500,
            longitudinalMeters: 2500
        )
        _cameraPosition = State(initialValue: .region(startRegion))
        _selectedCoordinate = State(initialValue: initialCoordinate)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Tap on the map to choose a location")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if let selectedCoordinate {
                            Marker("Selected location", coordinate: selectedCoordinate)
                        }
                    }
                    .mapStyle(.standard)
                    .onTapGesture { point in
                        if let coordinate = proxy.convert(point, from: .local) {
                            selectedCoordinate = coordinate
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let selectedCoordinate {
                    Text(String(format: "lat: %.5f, lon: %.5f", selectedCoordinate.latitude, selectedCoordinate.longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No location selected yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .navigationTitle("Choose location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search here") {
                        guard let selectedCoordinate else { return }
                        onConfirm(selectedCoordinate)
                    }
                    .disabled(selectedCoordinate == nil)
                }
            }
        }
    }
}
