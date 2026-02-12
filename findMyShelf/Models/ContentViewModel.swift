import SwiftUI
import FirebaseAuth
import SwiftData
import CoreLocation

@MainActor
final class ContentViewModel: ObservableObject {

    // MARK: - Managers

    @Published var locationManager = LocationManager()
    @Published var finder = StoreFinder()

    // MARK: - UI State

    @Published var showManualStoreSheet = false
    @Published var showReportSheet = false
    @Published var showLoginRequiredAlert = false

    @Published var quickQuery: String = ""
    @Published var savedStoreSearch: String = ""
    @Published var helpFilterText: String = ""

    @Published var isHelpExpanded: Bool = true

    @Published var selectedStoreId: String?
    @Published var previousSelectedStoreId: String?

    // MARK: - Computed

    var hasLocation: Bool {
        locationManager.currentLocation != nil
    }

    var isAuthorized: Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
}
