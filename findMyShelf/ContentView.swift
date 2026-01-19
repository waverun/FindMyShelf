import SwiftUI
import SwiftData
import CoreLocation
import PhotosUI
import UIKit

struct ContentView: View {
    private var hasLocation: Bool {
        locationManager.currentLocation != nil
    }

    private var isAuthorized: Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    @StateObject private var locationManager = LocationManager()
    @StateObject private var finder = StoreFinder()

    @Environment(\.modelContext) private var context
    @Query(sort: \Store.createdAt) private var stores: [Store]

    @AppStorage("selectedStoreId") private var selectedStoreId: String?

    private var selectedStore: Store? {
        guard let idString = selectedStoreId, let uuid = UUID(uuidString: idString) else { return nil }
        return stores.first(where: { $0.id == uuid })
    }

    private var bottomButtonsBar: some View {
        VStack(spacing: 10) {

            if let status = locationManager.authorizationStatus,
               status == .denied || status == .restricted {

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

            } else {

                HStack(spacing: 10) {
                    if locationManager.authorizationStatus == .notDetermined {
                        Button {
                            locationManager.requestPermission()
                        } label: {
                            Label("Allow location", systemImage: "location")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

//                    Button {
//                        locationManager.requestPermission()
//                    } label: {
//                        Label("Allow location", systemImage: "location")
//                            .frame(maxWidth: .infinity)
//                    }
//                    .buttonStyle(.bordered)

                    Button {
                        locationManager.startUpdating()
                    } label: {
                        Label("Refresh location", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isAuthorized)

//                    Button {
//                        locationManager.startUpdating()
//                    } label: {
//                        Label("Refresh location", systemImage: "arrow.clockwise")
//                            .frame(maxWidth: .infinity)
//                    }
//                    .buttonStyle(.bordered)
                }

                Button {
                    guard let loc = locationManager.currentLocation else { return }
                    finder.searchNearby(from: loc)
                } label: {
                    Label("Find nearby stores", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasLocation)

//                Button {
//                    guard let loc = locationManager.currentLocation else {
//                        // אפשר להוסיף פה Alert אם תרצה
//                        return
//                    }
//                    finder.searchNearby(from: loc)
//                } label: {
//                    Label("Find nearby stores", systemImage: "magnifyingglass")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    @State private var quickQuery: String = ""

    @State private var goToSearch: Bool = false
    @State private var goToAisles: Bool = false

    @State private var showPhotoSourceDialog: Bool = false
    @State private var isShowingCamera: Bool = false
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var isProcessingOCR: Bool = false

    @State private var bannerText: String?
    @State private var bannerIsError: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
//                        header

                        if selectedStore == nil {
                            storeDiscoverySection
                        } else {
                            selectedStoreSection
                            actionsSection
                        }

                        devLinksSection

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .safeAreaInset(edge: .bottom) {
                    if selectedStore == nil {
                        bottomButtonsBar
                    }
                }
                if let bannerText {
                    BannerView(text: bannerText, isError: bannerIsError) {
                        withAnimation { self.bannerText = nil }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle("FindMyShelf")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.startUpdating()
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker(isPresented: $isShowingCamera) { image in
                    processImage(image)
                }
            }
            .onChange(of: pickedPhotoItem) { _, newItem in
                if let item = newItem {
                    handlePickedPhoto(item)
                }
            }
            .background(
                Group {
                    if let store = selectedStore {
                        NavigationLink(isActive: $goToAisles) {
                            AisleListView(store: store)
                        } label: { EmptyView() }
                        NavigationLink(isActive: $goToSearch) {
                            ProductSearchView(store: store)
                        } label: { EmptyView() }
                    }
                }
            )
            .confirmationDialog(
                "Add aisle sign",
                isPresented: $showPhotoSourceDialog,
                titleVisibility: .visible
            ) {
                Button("Take photo") {
                    isShowingCamera = true
                }
                PhotosPicker(
                    selection: $pickedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text("Choose from library")
                }
            } message: {
                Text("You can take a photo in the store or choose an existing image.")
            }
        }
    }

    // MARK: - Header

//    private var header: some View {
//        VStack(alignment: .leading, spacing: 6) {
//            Text("Find your product")
//                .font(.title2.bold())
//
//            Text(selectedStore == nil ? "Choose an action" : "Choose a nearby store to get started")
//                .font(.subheadline)
//                .foregroundStyle(.secondary)
//        }
//        .padding(.vertical, 6)
//    }

    // MARK: - Store discovery

    private var storeDiscoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nearby stores")
                    .font(.headline)

                Spacer()

                Group {
                    if finder.isSearching {
                        ProgressView().scaleEffect(0.9)
                    } else {
                        ProgressView().scaleEffect(0.9).hidden()
                    }
                }

//                if finder.isSearching {
//                    ProgressView()
//                        .scaleEffect(0.9)
//                }
            }

            Group {
                if let status = locationManager.authorizationStatus {
                    if status == .denied || status == .restricted {
                        PermissionCard(
                            title: "Location permission required",
                            subtitle: "Without it, it's hard to find nearby stores. You can also choose manually.",
                            primaryButtonTitle: "Open Settings",
                            primaryAction: {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            },
                            secondaryButtonTitle: "Choose manually",
                            secondaryAction: {
                                showBanner("Coming soon: manual selection", isError: false)
                            }
                        )
                    } else {
//                        locationReadyControls
                    }
                } else {
//                    locationReadyControls
                }
            }

            if !finder.results.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(finder.results.prefix(12).enumerated()), id: \.element.id) { index, store in
                            StorePosterCard(
                                title: store.name,
                                subtitle: store.distance.map { formatDistance($0) },
                                colorIndex: index,
                                buttonTitle: "Choose",
                                buttonAction: {
                                    handleStoreChosen(store)
                                }
                            )
                        }

//                        ForEach(finder.results.prefix(12)) { store in
//                            StorePosterCard(
//                                title: store.name,
//                                subtitle: store.distance.map { formatDistance($0) },
//                                accentSeed: store.name,
//                                buttonTitle: "Select",
//                                buttonAction: {
//                                    handleStoreChosen(store)
////                                    withAnimation { showBanner("Selected: \(store.name)", isError: false) }
//                                }
//                            )
//                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
            } else {
                EmptyStateCard(
                    title: "No stores shown yet",
                    subtitle: "Tap \"Find nearby stores\" to see stores around you.",
                    icon: "location.viewfinder"
                )
            }
        }
    }

//    private var locationReadyControls: some View {
//        VStack(spacing: 10) {
//            HStack(spacing: 10) {
//                Button {
//                    locationManager.requestPermission()
//                } label: {
//                    Label("Allow location", systemImage: "location")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//
//                Button {
//                    locationManager.startUpdating()
//                } label: {
//                    Label("Refresh", systemImage: "arrow.clockwise")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.bordered)
//            }
//
//            Button {
//                guard let loc = locationManager.currentLocation else {
//                    showBanner("Location not available yet. Tap \"Allow location\" and then \"Refresh\".", isError: true)
//                    return
//                }
//                finder.searchNearby(from: loc)
//            } label: {
//                Label("Find nearby stores", systemImage: "magnifyingglass")
//                    .frame(maxWidth: .infinity)
//            }
//            .buttonStyle(.borderedProminent)
//
//            if let msg = locationManager.errorMessage {
//                Text(msg)
//                    .font(.footnote)
//                    .foregroundStyle(.red)
//            }
//        }
//    }

    // MARK: - Selected store

    private var selectedStoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your store")
                .font(.headline)

            if let store = selectedStore {
                SelectedStoreCard(
                    title: store.name,
                    accentSeed: store.name,
                    trailingButtonTitle: "Change",
                    trailingAction: {
                        selectedStoreId = nil
                        quickQuery = ""
//                        showBanner("Choose a different store", isError: false)
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            ActionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Search for a product", systemImage: "magnifyingglass")
                        .font(.headline)

                    HStack(spacing: 10) {
                        TextField("What are you looking for?", text: $quickQuery)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit {
                                startQuickSearch()
                            }

                        Button {
                            startQuickSearch()
                        } label: {
                            Text("Search")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Text("Tip: try \"milk\", \"rice\", \"chocolate\"…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ActionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Add aisle sign", systemImage: "camera.viewfinder")
                            .font(.headline)
                        Spacer()
                        if isProcessingOCR {
                            ProgressView()
                        }
                    }

                    Text("Take or select a photo of an aisle sign and the app will detect and add the aisle.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        guard selectedStore != nil else { return }
                        showPhotoSourceDialog = true
                    } label: {
                        Text("Upload image")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessingOCR)

                    Button {
                        goToAisles = true
                    } label: {
                        Text("Open aisle map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var devLinksSection: some View {
        Group {
            if let store = selectedStore {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tools")
                        .font(.headline)

                    HStack(spacing: 10) {
                        NavigationLink {
                            AisleListView(store: store)
                        } label: {
                            Label("Lines", systemImage: "list.bullet")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        NavigationLink {
                            ProductSearchView(store: store)
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Logic

    private func startQuickSearch() {
        let trimmed = quickQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard selectedStore != nil else {
            showBanner("Please select a store before searching", isError: true)
            return
        }
        goToSearch = true
    }

    private func handleStoreChosen(_ nearby: NearbyStore) {
        if let existing = stores.first(where: { s in
            s.name == nearby.name &&
            abs((s.latitude ?? 0) - nearby.coordinate.latitude) < 0.0005 &&
            abs((s.longitude ?? 0) - nearby.coordinate.longitude) < 0.0005
        }) {
            selectedStoreId = existing.id.uuidString
            return
        }

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
            showBanner("Failed to save the store", isError: true)
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    showBanner("Failed to load the image from the photo library", isError: true)
                }
                return
            }
            await MainActor.run {
                processImage(image)
            }
        }
    }

    private func processImage(_ image: UIImage) {
        guard let store = selectedStore else {
            showBanner("Please select a store before searching", isError: true)
            return
        }

        isProcessingOCR = true

        AisleOCRService.extractAisleInfo(from: image) { result in
            isProcessingOCR = false

            guard let rawTitle = result.title,
                  !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showBanner("No aisle title could be detected from the sign", isError: true)
                return
            }

            let name = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            let storeID = store.id
            let descriptor = FetchDescriptor<Aisle>(
                predicate: #Predicate<Aisle> { aisle in
                    aisle.storeId == storeID
                }
            )
//            let existing = FetchDescriptor<Aisle>(predicate: #Predicate { $0.storeId == store.id })

            let aisles = (try? context.fetch(descriptor)) ?? []
            if aisles.contains(where: { $0.nameOrNumber == name }) {
                showBanner("Aisle '(name)' already exists", isError: true)
                return
            }

            let aisle = Aisle(nameOrNumber: name, storeId: store.id, keywords: result.keywords)
            context.insert(aisle)

            do {
                try context.save()
                showBanner("Aisle added:", isError: false)
            } catch {
                showBanner("Failed to save the new aisle", isError: true)
            }
        }
    }

    private func showBanner(_ text: String, isError: Bool) {
        bannerIsError = isError
        withAnimation {
            bannerText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                if bannerText == text {
                    bannerText = nil
                }
            }
        }
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return String(format: "From %.0f ", meters)
        }
        return String(format: "%.1f k\"m", meters / 1000.0)
    }
}

// MARK: - UI building blocks

//private struct StorePosterCard: View {
//    let title: String
//    let subtitle: String?
//    let accentSeed: String
//    let buttonTitle: String
//    let buttonAction: () -> Void

private struct StorePosterCard: View {
    let title: String
    let subtitle: String?
    let colorIndex: Int
    let buttonTitle: String
    let buttonAction: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [color(for: colorIndex).opacity(0.95), color(for: colorIndex).opacity(0.55)],
//                    colors: [color(for: accentSeed).opacity(0.95), color(for: accentSeed).opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Button(buttonTitle, action: buttonAction)
                    .font(.subheadline.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.25))
            }
            .padding(16)
        }
        .frame(width: 280, height: 170)
        .shadow(radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)\(subtitle.map { ", \($0)" } ?? "")")
    }

    private func color(for index: Int) -> Color {
        let palette: [Color] = [
            .blue, .purple, .indigo, .teal, .mint, .pink, .orange
        ]
        return palette[index % palette.count]
    }
//    private func color(for seed: String) -> Color {
//        let hash = seed.unicodeScalars.reduce(0) { ($0 &* 131) &+ Int($1.value) }
//        let palette: [Color] = [.blue, .purple, .indigo, .teal, .mint, .pink, .orange]
//        return palette[abs(hash) % palette.count]
//    }
}

private struct SelectedStoreCard: View {
    let title: String
    let accentSeed: String
    let trailingButtonTitle: String
    let trailingAction: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                Text("Selected store")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(trailingButtonTitle, action: trailingAction)
                .buttonStyle(.bordered)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(color(for: accentSeed).opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func color(for seed: String) -> Color {
        let hash = seed.unicodeScalars.reduce(0) { ($0 &* 131) &+ Int($1.value) }
        let palette: [Color] = [.blue, .purple, .indigo, .teal, .mint, .pink, .orange]
        return palette[abs(hash) % palette.count]
    }
}

private struct ActionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
                    .shadow(radius: 10, y: 5)
            )
    }
}

private struct EmptyStateCard: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

private struct PermissionCard: View {
    let title: String
    let subtitle: String
    let primaryButtonTitle: String
    let primaryAction: () -> Void
    let secondaryButtonTitle: String
    let secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(primaryButtonTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                Button(secondaryButtonTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

private struct BannerView: View {
    let text: String
    let isError: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)

            Text(text)
                .font(.footnote)
                .lineLimit(2)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isError ? Color.red.opacity(0.18) : Color.green.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(radius: 10, y: 6)
    }
}

//import SwiftUI
//import CoreLocation
//import SwiftData
//
//struct ContentView: View {
//    @StateObject private var locationManager = LocationManager()
//
//    @Environment(\.modelContext) private var context
//    @Query(sort: \Store.createdAt) private var stores: [Store]
//
//    // מזהה החנות שנבחרה – נשמר ב-UserDefaults
//    @AppStorage("selectedStoreId") private var selectedStoreId: String?
//
//    // חנות נבחרת בפועל (אם קיימת ב-DB)
//    private var selectedStore: Store? {
//        guard let idString = selectedStoreId,
//              let uuid = UUID(uuidString: idString) else { return nil }
//        return stores.first(where: { $0.id == uuid })
//    }
//
//    var body: some View {
//        NavigationStack {
//            VStack(spacing: 24) {
//
//                Text("FindMyShelf")
//                    .font(.largeTitle.bold())
//
//                Text("שלב 1–2: מיקום + בחירת חנות")
//                    .font(.headline)
//                    .foregroundStyle(.secondary)
//
//                // סטטוס הרשאה
//                Group {
//                    if let status = locationManager.authorizationStatus {
//                        Text("סטטוס הרשאת מיקום: \(describe(status))")
//                    } else {
//                        Text("סטטוס הרשאת מיקום: לא ידוע עדיין")
//                    }
//                }
//                .font(.subheadline)
//
//                // מיקום נוכחי
//                Group {
//                    if let loc = locationManager.currentLocation {
//                        VStack(spacing: 4) {
//                            Text("המיקום שלך כרגע:")
//                                .font(.headline)
//                            Text(String(format: "Latitude: %.5f", loc.coordinate.latitude))
//                            Text(String(format: "Longitude: %.5f", loc.coordinate.longitude))
//                        }
//                    } else {
//                        Text("עוד אין מיקום. לחץ על \"אפשר מיקום\".")
//                            .multilineTextAlignment(.center)
//                    }
//                }
//                .font(.body)
//
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
//
//                    NavigationLink {
//                        AisleListView(store: store)
//                    } label: {
//                        Text("המשך למיפוי השורות")
//                            .frame(maxWidth: .infinity)
//                    }
//                    .buttonStyle(.bordered)
//
//                    NavigationLink {
//                        ProductSearchView(store: store)
//                    } label: {
//                        Text("חפש מוצר לפי שורות")
//                            .frame(maxWidth: .infinity)
//                    }
//                    .buttonStyle(.bordered)
//
//                } else {
//                    Text("עדיין לא נבחרה חנות.")
//                        .font(.footnote)
//                        .foregroundStyle(.secondary)
//                }
//
//                // חנות נבחרת מה-DB
////                if let store = selectedStore {
////                    VStack(spacing: 4) {
////                        Text("החנות שנבחרה:")
////                            .font(.headline)
////                        Text(store.name)
////                        if let lat = store.latitude, let lon = store.longitude {
////                            Text(String(format: "lat: %.5f, lon: %.5f", lat, lon))
////                                .font(.footnote)
////                                .foregroundStyle(.secondary)
////                        }
////                    }
////                    .padding()
////                    .background(.thinMaterial)
////                    .cornerRadius(12)
////                } else {
//                    Text("עדיין לא נבחרה חנות.")
//                        .font(.footnote)
//                        .foregroundStyle(.secondary)
//                }
//
//                // מעבר למסך חיפוש חנויות קרובות
//                if locationManager.currentLocation != nil {
//                    NavigationLink {
//                        NearbyStoresView(locationManager: locationManager) { nearby in
//                            handleStoreChosen(nearby)
//                        }
//                    } label: {
//                        Text("מצא חנויות קרובות ובחר \"זו החנות שלי\"")
//                            .multilineTextAlignment(.center)
//                    }
//                    .buttonStyle(.borderedProminent)
//                } else {
//                    Text("כדי לחפש חנויות קרובות, צריך קודם מיקום.")
//                        .font(.footnote)
//                        .foregroundStyle(.secondary)
//                        .multilineTextAlignment(.center)
//                }
//
//                if let msg = locationManager.errorMessage {
//                    Text(msg)
//                        .font(.footnote)
//                        .foregroundStyle(.red)
//                        .multilineTextAlignment(.center)
//                        .padding(.horizontal)
//                }
//
//                VStack(spacing: 12) {
//                    Button("אפשר מיקום") {
//                        locationManager.requestPermission()
//                    }
//                    .buttonStyle(.borderedProminent)
//
//                    Button("רענן מיקום") {
//                        locationManager.startUpdating()
//                    }
//                    .buttonStyle(.bordered)
//                }
//
//                Spacer()
//            }
//            .padding()
//            .navigationTitle("מסך ראשי")
//        }
////    }
//
//    // MARK: - Logic
//
//    /// מה עושים כשהמשתמש בוחר "זו החנות שלי" במסך החנויות הקרובות
//    private func handleStoreChosen(_ nearby: NearbyStore) {
//        // אופציה 1: לבדוק אם כבר יש חנות עם אותו שם וקואורדינטות דומות
//        if let existing = stores.first(where: { s in
//            s.name == nearby.name &&
//            abs((s.latitude ?? 0) - nearby.coordinate.latitude) < 0.0005 &&
//            abs((s.longitude ?? 0) - nearby.coordinate.longitude) < 0.0005
//        }) {
//            // משתמש בחנות קיימת
//            selectedStoreId = existing.id.uuidString
//        } else {
//            // יוצר חנות חדשה
//            let newStore = Store(
//                name: nearby.name,
//                latitude: nearby.coordinate.latitude,
//                longitude: nearby.coordinate.longitude
//            )
//            context.insert(newStore)
//            do {
//                try context.save()
//                selectedStoreId = newStore.id.uuidString
//            } catch {
//                print("Failed to save store:", error)
//            }
//        }
//    }
//
//    private func describe(_ status: CLAuthorizationStatus) -> String {
//        switch status {
//            case .notDetermined: return "לא הוחלט עדיין"
//            case .restricted:    return "מוגבל"
//            case .denied:        return "נשללה"
//            case .authorizedAlways: return "מאושרת תמיד"
//            case .authorizedWhenInUse: return "מאושרת בשימוש באפליקציה"
//            @unknown default:    return "לא מוכר"
//        }
//    }
//}
//
