import SwiftUI
import SwiftData
import CoreLocation
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var firebase: FirebaseService   // ✅ add

    private var hasLocation: Bool {
        locationManager.currentLocation != nil
    }

    @State private var pendingAisleToSelectID: UUID?

    @State private var showSelectedStoreAddress: Bool = false
    @State private var editingStore: Store?
    @State private var showEditStoreSheet: Bool = false

    @State private var showManualStoreSheet = false
    @State private var savedStoreSearch = ""

    @State private var pendingProductQuery: String = ""

    private var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
    }

    private var visionService: OpenAIAisleVisionService {
        OpenAIAisleVisionService(apiKey: apiKey)
    }

    private var previousStore: Store? {
        guard let idString = previousSelectedStoreId,
              let uuid = UUID(uuidString: idString) else { return nil }
        return stores.first(where: { $0.id == uuid })
    }

    private var isAuthorized: Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    @State private var pendingImage: UIImage?
    @State private var showConfirmImageSheet: Bool = false

    @FocusState private var isQuickQueryFocused: Bool

    @State private var showPhotosPicker: Bool = false

    @StateObject private var locationManager = LocationManager()
    @StateObject private var finder = StoreFinder()

    @Environment(\.modelContext) private var context
    @Query(sort: \Store.createdAt) private var stores: [Store]

    @AppStorage("selectedStoreId") private var selectedStoreId: String?
    @AppStorage("previousSelectedStoreId") private var previousSelectedStoreId: String?

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
                if selectedStoreId == nil, let prev = previousSelectedStoreId, !prev.isEmpty {
                    Button {
                        selectedStoreId = prev
                    } label: {
                        Label("Back to selected store", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

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

                    Button {
                        locationManager.startUpdating()
                    } label: {
                        Label("Refresh location", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isAuthorized)
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
                .padding(.top, 16)   // ← זה המרווח הנוסף
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
                .onTapGesture {
                    isQuickQueryFocused = false
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .top) {
                if let bannerText {
                    BannerView(text: bannerText, isError: bannerIsError) {
                        withAnimation { self.bannerText = nil }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
                }
            }
            .navigationTitle("FindMyShelf")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.startUpdating()
                }

                if let store = selectedStore {
                    Task { await startAislesSyncIfPossible(for: store) }
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker(isPresented: $isShowingCamera) { image in
                    processImage(image)
                }
            }
            .sheet(isPresented: $showConfirmImageSheet) {
                ConfirmImageSheet(
                    image: pendingImage,
                    onCancel: {
                        pendingImage = nil
                        pickedPhotoItem = nil
                        showConfirmImageSheet = false
                    },
                    onConfirm: { image in
                        pendingImage = nil
                        pickedPhotoItem = nil
                        showConfirmImageSheet = false
                        processImage(image)
                    }
                )
            }
            .onChange(of: pickedPhotoItem) { _, newItem in
                if let item = newItem {
                    handlePickedPhoto(item)
                }
            }
            .confirmationDialog(
                "Add aisle sign",
                isPresented: $showPhotoSourceDialog,
                titleVisibility: .visible
            ) {
                Button("Take photo") {
                    isQuickQueryFocused = false
                    isShowingCamera = true
                }

                Button("Choose from library") {
                    isQuickQueryFocused = false
                    showPhotosPicker = true
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You can take a photo in the store or choose an existing image.")
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isQuickQueryFocused = false
                    }
                }
            }
            .navigationDestination(isPresented: $goToAisles) {
                if let store = selectedStore {
                    AisleListView(store: store, initialSelectedAisleID: pendingAisleToSelectID)
                        .onDisappear {
                            pendingAisleToSelectID = nil
                        }
                }
            }
            
//            .navigationDestination(isPresented: $goToAisles) {
//                if let store = selectedStore {
//                    AisleListView(store: store)
//                }
//            }
            .navigationDestination(isPresented: $goToSearch) {
                if let store = selectedStore {
                    ProductSearchView(store: store, initialQuery: pendingProductQuery)
                }
            }

        }
        .onChange(of: selectedStoreId) { _, newValue in
            if newValue == nil {
                Task { @MainActor in stopAislesSync() }
                return
            }
            guard let store = selectedStore else { return }
            Task { await ensureStoreRemoteId(store)
                await startAislesSyncIfPossible(for: store) }
        }
        .onChange(of: selectedStoreId) { _, _ in
            guard let store = selectedStore else { return }
            Task { await ensureStoreRemoteId(store)
                await startAislesSyncIfPossible(for: store)
            }
        }
        .sheet(isPresented: $showManualStoreSheet) {
            ManualStoreSheet(
                existingStores: stores,
                onPickExisting: { store in
                    selectedStoreId = store.id.uuidString
                    showManualStoreSheet = false
                },
                onSaveNew: { name, address, city in
                    let newStore = Store(name: name, addressLine: address, city: city)
                    context.insert(newStore)
                    do {
                        try context.save()
                        selectedStoreId = newStore.id.uuidString
                        showManualStoreSheet = false
                    } catch {
                        showBanner("Failed to save the store", isError: true)
                    }
                },
                onDelete: { store in
                    // אם מוחקים חנות שנבחרה – נקה בחירה
                    if selectedStoreId == store.id.uuidString {
                        selectedStoreId = nil
                    }
                    if previousSelectedStoreId == store.id.uuidString {
                        previousSelectedStoreId = nil
                    }

                    context.delete(store)          // ✅ cascade ימחק aisles/products
                    do {
                        try context.save()
                    } catch {
                        showBanner("Failed to delete store", isError: true)
                    }
                }
            )
        }
        .sheet(isPresented: $showEditStoreSheet) {
            if let store = editingStore {
                EditStoreSheet(
                    store: store,
                    onSave: { updatedName, updatedAddress, updatedCity in
                        store.name = updatedName
                        store.addressLine = updatedAddress
                        store.city = updatedCity

                        do {
                            try context.save()
                            showBanner("Store updated", isError: false)

                            // אם נמחקה כתובת בזמן עריכה — סגור תצוגת כתובת
                            let addr = storeAddressLine(store) ?? ""
                            if addr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                showSelectedStoreAddress = false
                            }

                        } catch {
                            showBanner("Failed to update store", isError: true)
                        }
                    }
                )
            }
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $pickedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
    }

    // MARK: - Store discovery

    private var storeDiscoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nearby stores")
                    .font(.headline)

                Button("Add manually") {
                    showManualStoreSheet = true
                }
                .font(.subheadline)
                .buttonStyle(.bordered)

                Spacer()

                Group {
                    if finder.isSearching {
                        ProgressView().scaleEffect(0.9)
                    } else {
                        ProgressView().scaleEffect(0.9).hidden()
                    }
                }
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
                    }
                } else {
                }
            }

            if !finder.results.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(finder.results.prefix(12).enumerated()), id: \.element.id) { index, store in
                            let sub = [store.addressLine, store.distance.map(formatDistance)]
                                .compactMap { $0 }
                                .joined(separator: " • ")
                            StorePosterCard(
                                title: store.name,
//                                subtitle: store.distance.map { formatDistance($0) },
                                subtitle: sub.isEmpty ? nil : sub,
                                colorIndex: index,
                                isHighlighted: matchesPreviousStore(store),
                                badgeText: matchesPreviousStore(store) ? "Previously selected" : nil,
                                buttonTitle: "Choose",
                                buttonAction: {
                                    handleStoreChosen(store)
                                }
                            )
                        }
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

    // MARK: - Selected store

    private var selectedStoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your store")
                .font(.headline)

            if let store = selectedStore {
                SelectedStoreCard(
                    title: store.name,
                    address: storeAddressLine(store),
                    isAddressShown: showSelectedStoreAddress,
                    onToggleAddress: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showSelectedStoreAddress.toggle()
                        }
                    },
                    onEdit: {
                        editingStore = store
                        showEditStoreSheet = true
                    },
                    accentSeed: store.name,
                    trailingButtonTitle: "Change store",
                    trailingAction: {
                        previousSelectedStoreId = selectedStoreId
                        selectedStoreId = nil
                        quickQuery = ""
                        showSelectedStoreAddress = false
                    }
                )
            }
        }
    }

//    private var selectedStoreSection: some View {
//        VStack(alignment: .leading, spacing: 10) {
//            Text("Your store")
//                .font(.headline)
//
//            if let store = selectedStore {
//                SelectedStoreCard(
//                    title: store.name,
//                    accentSeed: store.name,
//                    trailingButtonTitle: "Change store",
//                    trailingAction: {
//                        previousSelectedStoreId = selectedStoreId   // שמור את מה שהיה
//                        selectedStoreId = nil                       // עבור למסך בחירת חנות
//                        quickQuery = ""
//                    }
//                )
//            }
//        }
//    }

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
                            .focused($isQuickQueryFocused)
                            .onSubmit {
                                isQuickQueryFocused = false      // סוגר מקלדת
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
//                            AisleListView(store: store)
                            AisleListView(store: store, initialSelectedAisleID: nil)
                        } label: {
                            Label("Lines", systemImage: "list.bullet")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        NavigationLink {
                            ProductSearchView(store: store, initialQuery: "")
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

    @MainActor
    private func stopAislesSync() {
        firebase.stopAislesListener()
        print("🛑 Stopped aisles listener")
    }

    @MainActor
    private func startAislesSyncIfPossible(for store: Store) async {
        // Make sure we have store.remoteId (either already saved or fetched/created)
        await ensureStoreRemoteId(store)

        guard let storeRemoteId = store.remoteId else {
            showBanner("Store is not synced to Firebase", isError: true)
            return
        }

        firebase.startAislesListener(
            storeRemoteId: storeRemoteId,
            localStoreId: store.id,
            context: context
        )

        print("✅ Started aisles listener for storeRemoteId:", storeRemoteId)
    }

    @MainActor
    private func syncCreatedAisleToFirebase(_ aisle: Aisle, store: Store) async {
        // If already synced, skip
        if aisle.remoteId != nil { return }

        // Make sure store has remoteId
        await ensureStoreRemoteId(store)
        guard let storeRemoteId = store.remoteId else {
            showBanner("Store is not synced to Firebase", isError: true)
            return
        }

        do {
            let rid = try await firebase.createAisle(storeRemoteId: storeRemoteId, aisle: aisle)
            aisle.remoteId = rid
            aisle.updatedAt = .now
            try? context.save()

            print("✅ Aisle synced to Firebase. aisleRemoteId:", rid)
        } catch {
            print("❌ Failed to create aisle in Firebase:", error)
            showBanner("Failed to sync aisle to Firebase", isError: true)
        }
    }

    @MainActor
    private func ensureStoreRemoteId(_ store: Store) async {
        if store.remoteId != nil { return }

        let addressCombined = [store.addressLine, store.city]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        do {
            let rid = try await firebase.fetchOrCreateStore(
                name: store.name,
                address: addressCombined.isEmpty ? store.addressLine : addressCombined,
                latitude: store.latitude,
                longitude: store.longitude
            )
            store.remoteId = rid
            try? context.save()
        } catch {
            showBanner("Failed to sync store to Firebase", isError: true)
        }
    }

    private func storeAddressLine(_ store: Store) -> String? {
        let parts = [store.addressLine, store.city]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }


    private func matchesPreviousStore(_ nearby: NearbyStore) -> Bool {
        guard let prev = previousStore,
              let lat = prev.latitude,
              let lon = prev.longitude else { return false }

        // התאמה עדינה: שם + קירבה גיאוגרפית קטנה
        let nameMatch = nearby.name == prev.name
        let latOk = abs(lat - nearby.coordinate.latitude) < 0.0007
        let lonOk = abs(lon - nearby.coordinate.longitude) < 0.0007

        return nameMatch && latOk && lonOk
    }

    private func startQuickSearch() {
        let trimmed = quickQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard selectedStore != nil else {
            showBanner("Please select a store before searching", isError: true)
            return
        }

        pendingProductQuery = trimmed
        goToSearch = true
    }

    private func handleStoreChosen(_ nearby: NearbyStore) {
        let lat = nearby.coordinate.latitude
        let lon = nearby.coordinate.longitude

        func distanceMeters(_ s: Store) -> Double? {
            guard let slat = s.latitude, let slon = s.longitude else { return nil }
            return CLLocation(latitude: slat, longitude: slon)
                .distance(from: CLLocation(latitude: lat, longitude: lon))
        }

        if let existing = stores.first(where: { s in
            guard let d = distanceMeters(s) else { return false }
            if d > 80 { return false }
            // אם יש כתובת – תן בונוס למי שמתאים
            if let a1 = s.addressLine?.lowercased(),
               let a2 = nearby.addressLine?.lowercased(),
               !a1.isEmpty, !a2.isEmpty {
                return a1 == a2
            }
            // fallback: שם+קרבה
            return s.name == nearby.name
        }) {
            selectedStoreId = existing.id.uuidString
            showSelectedStoreAddress = false
            return
        }

        let newStore = Store(
            name: nearby.name,
            latitude: lat,
            longitude: lon,
            addressLine: nearby.addressLine,
            city: nearby.city
        )
        context.insert(newStore)
        do {
            try context.save()
            selectedStoreId = newStore.id.uuidString
            showSelectedStoreAddress = false
        } catch {
            showBanner("Failed to save the store", isError: true)
        }
    }

//    private func handleStoreChosen(_ nearby: NearbyStore) {
//        if let existing = stores.first(where: { s in
//            s.name == nearby.name &&
//            abs((s.latitude ?? 0) - nearby.coordinate.latitude) < 0.0005 &&
//            abs((s.longitude ?? 0) - nearby.coordinate.longitude) < 0.0005
//        }) {
//            selectedStoreId = existing.id.uuidString
//            return
//        }
//
//        let newStore = Store(
//            name: nearby.name,
//            latitude: nearby.coordinate.latitude,
//            longitude: nearby.coordinate.longitude
//        )
//        context.insert(newStore)
//        do {
//            try context.save()
//            selectedStoreId = newStore.id.uuidString
//        } catch {
//            showBanner("Failed to save the store", isError: true)
//        }
//    }

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
                self.pendingImage = image
                self.showConfirmImageSheet = true
            }
        }
    }

    private func processImage(_ image: UIImage) {
        guard let store = selectedStore else {
            showBanner("Please select a store before uploading an image", isError: true)
            return
        }

        isQuickQueryFocused = false
        isProcessingOCR = true

        Task {
            do {
                guard !apiKey.isEmpty else {
                    throw NSError(domain: "Config", code: 0, userInfo: [NSLocalizedDescriptionKey: "OPENAI_API_KEY is missing"])
                }

                // JPEG דחוס כדי להקטין משקל (עלות/מהירות)
                guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
                    throw NSError(domain: "Image", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG"])
                }

                let result = try await visionService.analyzeAisle(imageJPEGData: jpeg)

                await MainActor.run {
                    isProcessingOCR = false

                    let titleOriginal = (result.title_original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let titleEn = (result.title_en ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                    let aisleCode = (result.aisle_code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                    // חייבים כותרת כלשהי כדי ליצור Aisle
                    let displayTitle = !aisleCode.isEmpty ? aisleCode : !titleEn.isEmpty ? titleEn : (!titleOriginal.isEmpty ? titleOriginal : "")

                    guard !displayTitle.isEmpty else {
                        showBanner("No aisle title could be detected from the sign", isError: true)
                        return
                    }

                    // בניית keywords: גם מקור וגם אנגלית + שתי הכותרות
                    var all = [String]()

//                    if let ko = result.keywords_original { all.append(contentsOf: ko) }
//                    if let ke = result.keywords_en { all.append(contentsOf: ke) }
                    all.append(contentsOf: result.keywords_original)
                    all.append(contentsOf: result.keywords_en)

                    if !titleOriginal.isEmpty { all.append(titleOriginal) }
                    if !titleEn.isEmpty { all.append(titleEn) }

                    // ניקוי/נרמול: trim, lowercased, הסרת ריקים, ייחוד
                    let normalized = all
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .map { $0.lowercased() }

                    let uniqueKeywords = Array(Set(normalized)).sorted()

                    // בדיקת כפילות לפי שם (אנגלית/מקור) — בגרסה שלך יש רק nameOrNumber, אז נבדוק מול displayTitle.
                    let storeID = store.id
                    let descriptor = FetchDescriptor<Aisle>(
                        predicate: #Predicate<Aisle> { aisle in
                            aisle.storeId == storeID
                        }
                    )
                    let aisles = (try? context.fetch(descriptor)) ?? []
                    if aisles.contains(where: { $0.nameOrNumber == displayTitle }) {
                        showBanner("Aisle '\(displayTitle)' already exists", isError: true)
                        return
                    }

                    // יצירה ושמירה
                    let aisle = Aisle(
                        nameOrNumber: displayTitle,
                        storeId: store.id,
                        keywords: uniqueKeywords
                    )

                    context.insert(aisle)
                    do {
                        try context.save()
                        showBanner("Aisle added: \(displayTitle)", isError: false)

                        Task { await syncCreatedAisleToFirebase(aisle, store: store) }

                        pendingAisleToSelectID = aisle.id
                        goToAisles = true
                    } catch {
                        showBanner("Failed to save the new aisle", isError: true)
                    }
                }

            } catch {
                await MainActor.run {
                    isProcessingOCR = false
                    showBanner("Failed to analyze image: \(error.localizedDescription)", isError: true)
                }
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
            return String(format: "%.0f meters ", meters)
        }
        return String(format: "%.1f k\"m", meters / 1000.0)
    }

//    private struct ConfirmImageSheet: View {
//        let image: UIImage?
//        let onCancel: () -> Void
//        let onConfirm: (UIImage) -> Void
//
//        var body: some View {
//            NavigationStack {
//                VStack(spacing: 16) {
//
//                    ZStack {
//                        RoundedRectangle(cornerRadius: 16, style: .continuous)
//                            .fill(Color.secondary.opacity(0.1))
//                            .frame(maxWidth: .infinity)
//                            .aspectRatio(3/4, contentMode: .fit)
//
//                        if let image {
//                            Image(uiImage: image)
//                                .resizable()
//                                .scaledToFit()
//                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
//                                .transition(.opacity)
//                        } else {
//                            ProgressView("Loading image…")
//                                .progressViewStyle(.circular)
//                        }
//                    }
//                    .padding(.horizontal, 16)
//                    .padding(.top, 8)
//
//                    Text("Use this photo?")
//                        .font(.headline)
//
//                    Text("The app will analyze the aisle sign and add an aisle.")
//                        .font(.footnote)
//                        .foregroundStyle(.secondary)
//                        .multilineTextAlignment(.center)
//                        .padding(.horizontal, 24)
//
//                    Spacer()
//                }
//                .navigationTitle("Confirm photo")
//                .navigationBarTitleDisplayMode(.inline)
//                .toolbar {
//                    ToolbarItem(placement: .cancellationAction) {
//                        Button("Cancel") { onCancel() }
//                    }
//                    ToolbarItem(placement: .confirmationAction) {
//                        Button("Use photo") {
//                            if let image { onConfirm(image) }
//                        }
//                        .disabled(image == nil)
//                    }
//                }
//            }
//        }
//    }

//    private struct ConfirmImageSheet: View {
//        let image: UIImage?
//        let onCancel: () -> Void
//        let onConfirm: (UIImage) -> Void
//
//        var body: some View {
//            NavigationStack {
//                VStack(spacing: 16) {
//                    if let image {
//                        Image(uiImage: image)
//                            .resizable()
//                            .scaledToFit()
//                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
//                            .padding(.horizontal, 16)
//                            .padding(.top, 8)
//
//                        Text("Use this photo?")
//                            .font(.headline)
//
//                        Text("The app will analyze the aisle sign and add an aisle.")
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                            .multilineTextAlignment(.center)
//                            .padding(.horizontal, 24)
//
//                    } else {
//                        Text("No image")
//                            .foregroundStyle(.secondary)
//                    }
//
//                    Spacer()
//                }
//                .navigationTitle("Confirm photo")
//                .navigationBarTitleDisplayMode(.inline)
//                .toolbar {
//                    ToolbarItem(placement: .cancellationAction) {
//                        Button("Cancel") { onCancel() }
//                    }
//                    ToolbarItem(placement: .confirmationAction) {
//                        Button("Use photo") {
//                            if let image { onConfirm(image) }
//                        }
//                        .disabled(image == nil)
//                    }
//                }
//            }
//        }
//    }
}

// MARK: - UI building blocks

//private struct StorePosterCard: View {
//    let title: String
//    let subtitle: String?
//    let colorIndex: Int
//    let isHighlighted: Bool
//    let badgeText: String?
//    let buttonTitle: String
//    let buttonAction: () -> Void
//
//    var body: some View {
//        let baseColor = color(for: colorIndex)
//
//        ZStack(alignment: .bottomLeading) {
//            RoundedRectangle(cornerRadius: 20, style: .continuous)
//                .fill(LinearGradient(
//                    colors: [baseColor.opacity(0.95), baseColor.opacity(0.55)],
//                    startPoint: .topLeading,
//                    endPoint: .bottomTrailing
//                ))
//                .overlay(
//                    RoundedRectangle(cornerRadius: 20, style: .continuous)
//                        .strokeBorder(isHighlighted ? .white.opacity(0.85) : .white.opacity(0.18),
//                                      lineWidth: isHighlighted ? 2 : 1)
//                )
//                .shadow(radius: isHighlighted ? 16 : 12, y: isHighlighted ? 8 : 6)
//                .scaleEffect(isHighlighted ? 1.03 : 1.0)
//                .animation(.easeInOut(duration: 0.15), value: isHighlighted)
//
//            VStack(alignment: .leading, spacing: 10) {
//                VStack(alignment: .leading, spacing: 6) {
//
//                    if let badgeText {
//                        Text(badgeText)
//                            .font(.caption2.bold())
//                            .padding(.horizontal, 8)
//                            .padding(.vertical, 4)
//                            .background(.white.opacity(0.22))
//                            .clipShape(Capsule())
//                            .foregroundStyle(.white)
//                    }
//
//                    Text(title)
//                        .font(.headline)
//                        .foregroundStyle(.white)
//                        .lineLimit(2)
//
//                    if let subtitle {
//                        Text(subtitle)
//                            .font(.subheadline)
//                            .foregroundStyle(.white.opacity(0.85))
//                    }
//                }
//
//                Button(buttonTitle, action: buttonAction)
//                    .font(.subheadline.bold())
//                    .buttonStyle(.borderedProminent)
//                    .tint(.white.opacity(0.25))
//            }
//            .padding(16)
//        }
//        .frame(width: 280, height: 170)
//        .accessibilityElement(children: .combine)
//    }
//
//    private func color(for index: Int) -> Color {
//        let palette: [Color] = [
//            .blue, .purple, .indigo, .teal, .mint, .pink, .orange
//        ]
//        return palette[index % palette.count]
//    }
//}

//private struct SelectedStoreCard: View {
//    let title: String
//    let accentSeed: String
//    let trailingButtonTitle: String
//    let trailingAction: () -> Void
//
//    var body: some View {
//        HStack(alignment: .center) {
//            VStack(alignment: .leading, spacing: 6) {
//                Text(title)
//                    .font(.title3.bold())
//                Text("Selected store")
//                    .font(.footnote)
//                    .foregroundStyle(.secondary)
//            }
//
//            Spacer()
//
//            Button(action: trailingAction) {
//                Label("Change store", systemImage: "arrow.triangle.2.circlepath")
//            }
//            .buttonStyle(.bordered)
//        }
//        .padding(16)
//        .background(
//            RoundedRectangle(cornerRadius: 20, style: .continuous)
//                .fill(.thinMaterial)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 20, style: .continuous)
//                        .strokeBorder(color(for: accentSeed).opacity(0.25), lineWidth: 1)
//                )
//        )
//    }
//
//    private func color(for seed: String) -> Color {
//        let hash = seed.unicodeScalars.reduce(0) { ($0 &* 131) &+ Int($1.value) }
//        let palette: [Color] = [.blue, .purple, .indigo, .teal, .mint, .pink, .orange]
//        return palette[abs(hash) % palette.count]
//    }
//}

//private struct SelectedStoreCard: View {
//    let title: String
//    let address: String?
//    let isAddressShown: Bool
//    let onToggleAddress: () -> Void
//
//    let accentSeed: String
//    let trailingButtonTitle: String
//    let trailingAction: () -> Void
//
//    var body: some View {
//        HStack(alignment: .center) {
//            VStack(alignment: .leading, spacing: 6) {
//
//                // רק הכותרת לחיצה (ולא כל הכרטיס)
//                Button(action: onToggleAddress) {
//                    HStack(spacing: 6) {
//                        Text(title)
//                            .font(.title3.bold())
//                            .foregroundStyle(.primary)
//
//                        if address != nil {
//                            Image(systemName: isAddressShown ? "chevron.up" : "chevron.down")
//                                .font(.caption.weight(.semibold))
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//                }
//                .buttonStyle(.plain)
//
//                Text("Selected store")
//                    .font(.footnote)
//                    .foregroundStyle(.secondary)
//
//                if isAddressShown, let address, !address.isEmpty {
//                    Text(address)
//                        .font(.footnote)
//                        .foregroundStyle(.secondary)
//                        .transition(.opacity.combined(with: .move(edge: .top)))
//                }
//            }
//
//            Spacer()
//
//            Button(action: trailingAction) {
//                Label(trailingButtonTitle, systemImage: "arrow.triangle.2.circlepath")
//            }
//            .buttonStyle(.bordered)
//        }
//        .padding(16)
//        .background(
//            RoundedRectangle(cornerRadius: 20, style: .continuous)
//                .fill(.thinMaterial)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 20, style: .continuous)
//                        .strokeBorder(color(for: accentSeed).opacity(0.25), lineWidth: 1)
//                )
//        )
//    }
//
//    private func color(for seed: String) -> Color {
//        let hash = seed.unicodeScalars.reduce(0) { ($0 &* 131) &+ Int($1.value) }
//        let palette: [Color] = [.blue, .purple, .indigo, .teal, .mint, .pink, .orange]
//        return palette[abs(hash) % palette.count]
//    }
//}

private struct SelectedStoreCard: View {
    let title: String
    let address: String?
    let isAddressShown: Bool
    let onToggleAddress: () -> Void
    let onEdit: () -> Void

    let accentSeed: String
    let trailingButtonTitle: String
    let trailingAction: () -> Void

    private var hasAddress: Bool {
        let a = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !a.isEmpty
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {

                // ✅ אם אין כתובת: השם הוא Text (לא לחיץ)
                // ✅ אם יש כתובת: השם הוא Button שמטגל כתובת
                Group {
                    if hasAddress {
                        Button(action: onToggleAddress) {
                            titleRow
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in onEdit() }
                        )
                    } else {
                        titleRow
                            .onLongPressGesture(minimumDuration: 0.5) {
                                onEdit()
                            }
                    }
                }

                Text("Selected store")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if isAddressShown, hasAddress, let address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer()

            Button(action: trailingAction) {
                Label(trailingButtonTitle, systemImage: "arrow.triangle.2.circlepath")
            }
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

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)

            if hasAddress {
                Image(systemName: isAddressShown ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func color(for seed: String) -> Color {
        let hash = seed.unicodeScalars.reduce(0) { ($0 &* 131) &+ Int($1.value) }
        let palette: [Color] = [.blue, .purple, .indigo, .teal, .mint, .pink, .orange]
        return palette[abs(hash) % palette.count]
    }
}


//private struct ActionCard<Content: View>: View {
//    @ViewBuilder var content: Content
//
//    var body: some View {
//        content
//            .padding(16)
//            .frame(maxWidth: .infinity)
//            .background(
//                RoundedRectangle(cornerRadius: 20, style: .continuous)
//                    .fill(.thinMaterial)
//                    .shadow(radius: 10, y: 5)
//            )
//    }
//}

private struct EditStoreSheet: View {
    let store: Store
    let onSave: (_ name: String, _ address: String?, _ city: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var addressLine: String
    @State private var city: String

    init(store: Store,
         onSave: @escaping (_ name: String, _ address: String?, _ city: String?) -> Void) {
        self.store = store
        self.onSave = onSave
        _name = State(initialValue: store.name)
        _addressLine = State(initialValue: store.addressLine ?? "")
        _city = State(initialValue: store.city ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Store") {
                    TextField("Store name", text: $name)
                    TextField("Address", text: $addressLine)
                    TextField("City", text: $city)
                }

                Section {
                    Button("Save") {
                        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !n.isEmpty else { return }

                        let a = addressLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        let c = city.trimmingCharacters(in: .whitespacesAndNewlines)

                        onSave(n,
                               a.isEmpty ? nil : a,
                               c.isEmpty ? nil : c)

                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Edit store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

//private struct PermissionCard: View {
//    let title: String
//    let subtitle: String
//    let primaryButtonTitle: String
//    let primaryAction: () -> Void
//    let secondaryButtonTitle: String
//    let secondaryAction: () -> Void
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 10) {
//            Text(title)
//                .font(.headline)
//            Text(subtitle)
//                .font(.subheadline)
//                .foregroundStyle(.secondary)
//
//            HStack(spacing: 10) {
//                Button(primaryButtonTitle, action: primaryAction)
//                    .buttonStyle(.borderedProminent)
//                Button(secondaryButtonTitle, action: secondaryAction)
//                    .buttonStyle(.bordered)
//            }
//        }
//        .padding(16)
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .background(
//            RoundedRectangle(cornerRadius: 20, style: .continuous)
//                .fill(.thinMaterial)
//        )
//    }
//}

//private struct BannerView: View {
//    let text: String
//    let isError: Bool
//    let onClose: () -> Void
//
//    var body: some View {
//        HStack(spacing: 10) {
//            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
//                .symbolRenderingMode(.hierarchical)
//
//            Text(text)
//                .font(.footnote)
//                .lineLimit(2)
//
//            Spacer()
//
//            Button(action: onClose) {
//                Image(systemName: "xmark")
//                    .font(.footnote.bold())
//            }
//        }
//        .padding(12)
//        .background(
//            RoundedRectangle(cornerRadius: 16, style: .continuous)
//                .fill(isError ? Color.red.opacity(0.18) : Color.green.opacity(0.16))
//                .overlay(
//                    RoundedRectangle(cornerRadius: 16, style: .continuous)
//                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
//                )
//        )
//        .shadow(radius: 10, y: 6)
//    }
//}
