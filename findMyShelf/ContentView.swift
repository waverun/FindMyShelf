import SwiftUI
import FirebaseAuth
import FirebaseFunctions
import SwiftData
import CoreLocation
import PhotosUI
import UIKit

enum AppColors {
    static let logoOrangeLight = Color(red: 254/255, green: 134/255, blue: 12/255) // #FE860C
    static let logoOrangeDark  = Color(red: 241/255, green:  79/255, blue: 12/255) // #F14F0C
    static let headingColor    = logoOrangeLight
}

struct ContentView: View {
    @EnvironmentObject private var firebase: FirebaseService   // ✅ add
    @EnvironmentObject private var uploadFlow: UploadFlowCoordinator

    // MARK: - Reporting (store-level)
    
#if DEBUG
    @State private var goToReportsAdmin: Bool = false
#endif

    @State private var shouldRestoreSelectedStoreGuideCard: Bool = false

    @State private var didShowSelectedStoreFirstTimeThisRun: Bool = false

    @State private var showReportSheet: Bool = false
    @State private var selectedStoreUpdatedByUserId: String? = nil
    
    @State private var showLoginRequiredAlert = false
    @State private var loginAppleCoordinator = AppleSignInCoordinator()
    
    @StateObject private var ocr = AisleOCRController()
    
    private var hasLocation: Bool {
        locationManager.currentLocation != nil
    }
    
    @State private var ensuringStoreRemoteId = Set<UUID>()
    
    @State private var pendingAisleToSelectID: UUID?
    
    @State private var showSelectedStoreAddress: Bool = false
    @State private var editingStore: Store?
    @State private var showEditStoreSheet: Bool = false
    
    @State private var showManualStoreSheet = false
    @State private var savedStoreSearch = ""
    @State private var helpFilterText: String = ""

    @State private var pendingProductQuery: String = ""
    
//    private var apiKey: String {
//        Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
//    }
    
//                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       }

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

    @State private var didSeeSelectedStoreGuide: Bool = false
    @State private var didSeeChooseStoreGuide: Bool = false

    @State private var showDemoUploadSheet: Bool = false

    @State private var debugFunctionOutput: String = ""
    @State private var isCallingFunction: Bool = false

    private var functions: Functions {
        Functions.functions(region: "us-central1")
    }

    @StateObject private var locationManager = LocationManager()
    @StateObject private var finder = StoreFinder()
    
    @Environment(\.modelContext) private var context
    @Query(sort: \Store.createdAt) private var stores: [Store]

    @AppStorage("showDemoUploadChooser") private var showDemoUploadChooser: Bool = true

    @AppStorage("showChooseStoreGuideCard") private var showChooseStoreGuideCard: Bool = true
    @AppStorage("showSelectedStoreGuideCard") private var showSelectedStoreGuideCard: Bool = true

    @AppStorage("isHelpExpanded") private var isHelpExpanded: Bool = true

    @AppStorage("selectedStoreId") private var selectedStoreId: String?
    @AppStorage("previousSelectedStoreId") private var previousSelectedStoreId: String?
    
    private var selectedStore: Store? {
        guard let idString = selectedStoreId, let uuid = UUID(uuidString: idString) else { return nil }
        return stores.first(where: { $0.id == uuid })
    }
    
    private var bottomButtonsBar: some View {
        HStack(spacing: 18) {
            
            // If location is blocked, the only meaningful action here is opening Settings.
            if let status = locationManager.authorizationStatus,
               status == .denied || status == .restricted {
                
                IconBarButton(
                    systemImage: "gearshape",
                    accessibilityLabel: "Open Settings",
                    isEnabled: true
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                
                Spacer()
                
            } else {
                
                // Back to previous selected store
                if selectedStoreId == nil, let prev = previousSelectedStoreId, !prev.isEmpty {
                    IconBarButton(
                        systemImage: "arrow.uturn.backward",
                        accessibilityLabel: "Back to selected store",
                        isEnabled: true
                    ) {
                        selectedStoreId = prev
                    }
                }
                
                // Allow location (only when not determined)
                if locationManager.authorizationStatus == .notDetermined {
                    IconBarButton(
                        systemImage: "location",
                        accessibilityLabel: "Allow location",
                        isEnabled: true
                    ) {
                        locationManager.requestPermission()
                    }
                }
                
                // Refresh location
                IconBarButton(
                    systemImage: "arrow.clockwise",
                    accessibilityLabel: "Refresh location",
                    isEnabled: isAuthorized
                ) {
                    locationManager.startUpdating()
                }
                
                // Find nearby
                IconBarButton(
                    systemImage: "magnifyingglass",
                    accessibilityLabel: "Find nearby stores",
                    isEnabled: hasLocation,
                    isPrimary: true
                ) {
                    guard let loc = locationManager.currentLocation else { return }
                    finder.searchNearby(from: loc)
                }
                
                IconBarButton(
                    systemImage: "exclamationmark.bubble",
                    accessibilityLabel: "Report a user",
                    isEnabled: true
                ) {
                    showReportSheet = true
                }
                
#if DEBUG
                IconBarButton(
                    systemImage: "ladybug",
                    accessibilityLabel: "Reports admin (Debug)",
                    isEnabled: true
                ) {
                    goToReportsAdmin = true
                }
#endif
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    private var selectedStoreButtonsBar: some View {
        HStack(spacing: 18) {
            
            // Back / Change store
            IconBarButton(
                systemImage: "arrow.uturn.backward",
                accessibilityLabel: "Change store",
                isEnabled: true
            ) {
                previousSelectedStoreId = selectedStoreId
                selectedStoreId = nil
                quickQuery = ""
                showSelectedStoreAddress = false
            }
            
            // Open aisle map (aka "Lines")
            IconBarButton(
                systemImage: "list.bullet",
                accessibilityLabel: "Open aisle map",
                isEnabled: (selectedStore != nil),
                isPrimary: true
            ) {
                goToAisles = true
            }
            
            // Product search screen
            IconBarButton(
                systemImage: "magnifyingglass",
                accessibilityLabel: "Search products",
                isEnabled: (selectedStore != nil)
            ) {
                pendingProductQuery = ""      // optional: start blank
                goToSearch = true
            }
            
            // Add aisle sign (camera)
            IconBarButton(
                systemImage: "camera.viewfinder",
                accessibilityLabel: "Add aisle sign (upload image)",
                isEnabled: (selectedStore != nil) && !ocr.isProcessingOCR
            ) {
                guard selectedStore != nil else { return }
                
                if Auth.auth().currentUser == nil ||
                    (Auth.auth().currentUser?.isAnonymous ?? true) {
                    showLoginRequiredAlert = true
                    return
                }
                showPhotoSourceDialog = true
            }
            
            IconBarButton(
                systemImage: "exclamationmark.bubble",
                accessibilityLabel: "Report a user",
                isEnabled: true
            ) {
                showReportSheet = true
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    private struct IconBarButton: View {
        let systemImage: String
        let accessibilityLabel: String
        let isEnabled: Bool
        var isPrimary: Bool = false
        let action: () -> Void
        
        var body: some View {
            // Use a container so a long-press hint works even when the button is "disabled".
            // Long-press shows a description and performs no action.
            ZStack {
                if isEnabled {
                    Button(action: action) {
                        icon
                    }
                    .buttonStyle(.plain)
                } else {
                    icon
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .opacity(isEnabled ? 1.0 : 0.45)
            .accessibilityLabel(accessibilityLabel)
            .contextMenu {
                Text(accessibilityLabel)
            }
        }
        
        private var icon: some View {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolVariant(isPrimary ? .fill : .none)
        }
    }
    
    @State private var quickQuery: String = ""
    
    @State private var goToSearch: Bool = false
    @State private var goToAisles: Bool = false
    
    @State private var showPhotoSourceDialog: Bool = false
    @State private var isShowingCamera: Bool = false
    @State private var pickedPhotoItem: PhotosPickerItem?
    
    @State private var bannerText: String?
    @State private var bannerIsError: Bool = false
    
    // MARK: - Keyboard
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
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
                        } else {
                            selectedStoreButtonsBar
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            isQuickQueryFocused = false
                            dismissKeyboard()
                        }
                    )
                    .onChange(of: uploadFlow.requestUpload) { _, v in
                        guard v else { return }
                        uploadFlow.requestUpload = false

                        // do exactly what your Upload button does:
                        if Auth.auth().currentUser == nil || (Auth.auth().currentUser?.isAnonymous ?? true) {
                            showLoginRequiredAlert = true
                            return
                        }
                        if showDemoUploadChooser {
                            showDemoUploadSheet = true
                        } else {
                            showPhotoSourceDialog = true
                        }
                    }
                    .onChange(of: isHelpExpanded) { _, newValue in
                        // If there are no stores yet, we still allow hiding tips.
                        // Just clear the store search field to avoid a "search stores" mode with no data.
                        if newValue == false && finder.results.isEmpty {
                            savedStoreSearch = ""
                        }

                        // When switching modes, clear the other search field and close keyboard.
                        if newValue {
                            savedStoreSearch = ""
                        } else {
                            helpFilterText = ""
                        }
                        isQuickQueryFocused = false
                        dismissKeyboard()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    // לדוגמה: אחרי .ignoresSafeArea(.keyboard, edges: .bottom) ב‑ScrollView
                    .onChange(of: isQuickQueryFocused) { _, isFocused in
                        DispatchQueue.main.async {
                            withAnimation {
                                if isFocused {
                                    proxy.scrollTo("quickQueryField", anchor: .top)
                                } else {
                                    proxy.scrollTo("quickQueryField", anchor: .center)
                                }
                            }
                        }
                    }
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
                    setupNavigationTitleColor(color: AppColors.logoOrangeDark)
                    if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                        locationManager.startUpdating()
                    }

                    if let store = selectedStore {
                        Task { await startAislesSyncIfPossible(for: store) }

                        Task { @MainActor in
                            await ensureStoreRemoteId(store)
                            if let rid = store.remoteId {
                                do {
                                    let attr = try await firebase.fetchStoreAttribution(storeRemoteId: rid)
                                    selectedStoreUpdatedByUserId = attr.updatedBy
                                } catch {
                                    selectedStoreUpdatedByUserId = nil
                                }
                            }
                        }
                    }
                }
                .sheet(isPresented: $showReportSheet) {
                    ReportUserSheet(
                        title: selectedStore != nil ? "Report last editor" : "Report",
                        onCancel: { showReportSheet = false },
                        onSubmit: { reason, details in

                            guard let reporterId = Auth.auth().currentUser?.uid else {
                                showReportSheet = false
                                showLoginRequiredAlert = true
                                return
                            }

                            // Target = last editor of selected store (best available signal right now)
                            let targetUserId = selectedStoreUpdatedByUserId ?? "unknown_target"
                            let storeRid = selectedStore?.remoteId

                            Task { @MainActor in
                                do {
                                    try await firebase.submitUserReport(
                                        reportedUserId: targetUserId,
                                        reporterUserId: reporterId,
                                        reason: reason ?? "no_reason_selected",
                                        details: details,
                                        storeRemoteId: storeRid,
                                        context: selectedStore != nil ? "store_last_editor" : "general"
                                    )
                                    showReportSheet = false
                                    showBanner("Report submitted. Thank you.", isError: false)
                                } catch {
                                    showReportSheet = false
                                    showBanner("Failed to submit report.", isError: true)
                                }
                            }
                        }
                    )
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
                .alert("Login required", isPresented: $showLoginRequiredAlert) {
                    Button("Cancel", role: .cancel) {}

                    Button("Continue with Google") {
                        Task { @MainActor in
                            try? await signInWithGoogle()
                        }
                    }

                    Button("Continue with Apple") {
                        Task { @MainActor in
                            loginAppleCoordinator.start()
                        }
                    }
                } message: {
                    Text("Please sign in to upload images.")
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AuthButtons()
                    }

                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isQuickQueryFocused = false
                            dismissKeyboard()
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

                .navigationDestination(isPresented: $goToSearch) {
                    if let store = selectedStore {
                        ProductSearchView(store: store, initialQuery: pendingProductQuery)
                    }
                }
#if DEBUG
                .navigationDestination(isPresented: $goToReportsAdmin) {
                    ReportsAdminView(firebase: firebase)
                }
#endif
            }
            .onChange(of: selectedStoreId) { _, newValue in
                //            if newValue != nil {
                //                showFirstGuideNow = false
                //            }

                if newValue == nil {
                    Task { @MainActor in stopAislesSync() }
                    return
                }
                guard let store = selectedStore else { return }
                Task { await ensureStoreRemoteId(store)
                    Task { @MainActor in
                        guard let rid = store.remoteId else {
                            selectedStoreUpdatedByUserId = nil
                            return
                        }
                        do {
                            let attr = try await firebase.fetchStoreAttribution(storeRemoteId: rid)
                            selectedStoreUpdatedByUserId = attr.updatedBy
                        } catch {
                            selectedStoreUpdatedByUserId = nil
                        }
                    }
                    await startAislesSyncIfPossible(for: store) }
            }
            .sheet(isPresented: $showManualStoreSheet) {
                ManualStoreSheet(
                    existingStores: stores,
                    onPickExisting: { store in
                        selectedStoreId = store.id.uuidString
                        showManualStoreSheet = false
                    },
                    onSaveNew: { name, address, city in
                        if Auth.auth().currentUser == nil ||
                            (Auth.auth().currentUser?.isAnonymous ?? true) {
                            showManualStoreSheet = false
                            showLoginRequiredAlert = true
                            return
                        }

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

                        Task { @MainActor in
                            await deleteStoreEverywhere(store)
                            showManualStoreSheet = false
                        }
                    },
                    onUpdate: { store, name, address, city in
                        // 1) Update locally
                        store.name = name
                        store.addressLine = address
                        store.city = city

                        do {
                            try context.save()
                            showBanner("Store updated", isError: false)
                        } catch {
                            showBanner("Failed to update store locally", isError: true)
                            return
                        }

                        // 2) Update Firebase
                        Task { @MainActor in
                            // ensure remoteId exists
                            await ensureStoreRemoteId(store)

                            guard let rid = store.remoteId else {
                                showBanner("Store is not synced to Firebase", isError: true)
                                return
                            }

                            do {
                                try await firebase.updateStore(
                                    storeRemoteId: rid,
                                    name: store.name,
                                    address: store.addressLine,
                                    city: store.city
                                )
                            } catch {
                                showBanner("Failed to update store in Firebase", isError: true)
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showDemoUploadSheet) {
                DemoUploadSheet(
                    onPickDemoImageNamed: { name in
                        guard let img = UIImage(named: name) else {
                            showBanner("Missing demo image asset: \(name)", isError: true)
                            return
                        }
                        pendingImage = img
                        showDemoUploadSheet = false
                        showConfirmImageSheet = true
                    },
                    onDontShowAgain: {
                        showDemoUploadChooser = false
                        showDemoUploadSheet = false
                        showPhotoSourceDialog = true   // recommended: continue now
                    },
                    onGotIt: {
                        showDemoUploadSheet = false
                        showPhotoSourceDialog = true
                    }
                )
            }
            .sheet(isPresented: $showEditStoreSheet) {
                if let store = editingStore {
                    EditStoreSheet(
                        store: store,
                        onSave: { updatedName, updatedAddress, updatedCity in

                            // 1) Update locally
                            store.name = updatedName
                            store.addressLine = updatedAddress
                            store.city = updatedCity

                            do {
                                try context.save()
                                showBanner("Store updated", isError: false)

                                let addr = storeAddressLine(store) ?? ""
                                if addr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    showSelectedStoreAddress = false
                                }
                            } catch {
                                showBanner("Failed to update store locally", isError: true)
                                return
                            }

                            // 2) Update Firebase  ✅ (same as ManualStoreSheet)
                            Task { @MainActor in
                                await ensureStoreRemoteId(store)

                                guard let rid = store.remoteId else {
                                    showBanner("Store is not synced to Firebase", isError: true)
                                    return
                                }

                                do {
                                    try await firebase.updateStore(
                                        storeRemoteId: rid,
                                        name: store.name,
                                        address: store.addressLine,
                                        city: store.city
                                    )
                                } catch {
                                    showBanner("Failed to update store in Firebase", isError: true)
                                }
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
    }
    
    // MARK: - Store discovery
    
    private var storeDiscoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nearby stores")
                    .font(.headline)
                    .foregroundStyle(AppColors.headingColor)
                Button("Add manually") {
                    showManualStoreSheet = true
                }
                .font(.subheadline)
                .buttonStyle(.bordered)
                
                Spacer()
                
//                Group {
//                    if finder.isSearching {
//                        ProgressView().scaleEffect(0.9)
//                    } else {
//                        ProgressView().scaleEffect(0.9).hidden()
//                    }
//                }
            }
            if showChooseStoreGuideCard && !didSeeChooseStoreGuide {
                let shouldShowEnableLocationHint = (locationManager.authorizationStatus == .notDetermined)

                ChooseStoreGuideCard(
                    showEnableLocationHint: shouldShowEnableLocationHint,
                    onGotIt: {
                        didSeeChooseStoreGuide = true
                    },
                    onDontShowAgain: {
                        showChooseStoreGuideCard = false
                        didSeeChooseStoreGuide = true
                    }
                )
                .padding(.top, 4)
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
            
            // ✅ Help / Tips (fills empty space on first screen)
            //            helpTipsSection
            
            // Placeholder must reflect the *active* search mode.
            // If there are no stores yet, we always keep it as tips search.
            let hasAnyStores = !finder.results.isEmpty
            let isStoreSearchMode = (!isHelpExpanded) && hasAnyStores
            let searchPlaceholder = isStoreSearchMode ? "Search stores" : "Search tips"
            
            HelpTipsSection(
                filterText: Binding(
                    get: { isHelpExpanded ? helpFilterText : savedStoreSearch },
                    set: { newValue in
                        if isHelpExpanded {
                            helpFilterText = newValue
                        } else {
                            savedStoreSearch = newValue
                        }
                    }
                ),
                isExpanded: $isHelpExpanded,
                searchPlaceholder: searchPlaceholder
            )
            if !(isHelpExpanded) && filteredNearbyStores.isEmpty && !finder.results.isEmpty {
                EmptyStateCard(
                    title: "No matching stores",
                    subtitle: "Try a different store name.",
                    icon: "magnifyingglass"
                )
            } else if !finder.results.isEmpty {
                VStack(spacing: 12) {
                    ForEach(Array(filteredNearbyStores.prefix(12).enumerated()), id: \.element.id) { index, store in
                        let sub = [store.addressLine, store.distance.map(formatDistance)]
                            .compactMap { $0 }
                            .joined(separator: " • ")
                        StorePosterCard(
                            title: store.name,
                            subtitle: sub.isEmpty ? nil : sub,
                            colorIndex: index,
                            isHighlighted: matchesPreviousStore(store),
                            badgeText: matchesPreviousStore(store) ? "Previously selected" : nil,
                            buttonTitle: "Choose",
                            buttonAction: {
                                handleStoreChosen(store)
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 6)
            } else {
                EmptyStateCard(
                    title: "No stores shown yet",
                    subtitle: "Tap \"Find nearby stores\" to see stores around you.",
                    icon: "location.viewfinder"
                )
                .padding(.bottom, 6)
                // Keep the tips visible even when there are no results
                // (already shown above, but this adds a clear visual anchor)
                Divider().padding(.vertical, 4)

                if finder.isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Spacer()
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
            }
        }
    }
    private var filteredNearbyStores: [NearbyStore] {
        let q = savedStoreSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return finder.results }
        return finder.results.filter { store in
            let haystack = [store.name, store.addressLine, store.city]
                .compactMap { $0 }
                .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(q)
        }
    }
    
    // MARK: - Selected store

    private var selectedStoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your store")
                .font(.headline)
                .foregroundStyle(AppColors.headingColor)

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

                if showSelectedStoreGuideCard && !didSeeSelectedStoreGuide {
                    SelectedStoreGuideCard(
                        aisleCount: aisleCount(for: store),
                        onGotIt: {
                            didSeeSelectedStoreGuide = true
                        },
                        onDontShowAgain: {
                            showSelectedStoreGuideCard = false
                            didSeeSelectedStoreGuide = true
                        }
                    )
                    .padding(.top, 6)
                }
            }
        }
    }

    // MARK: - Actions
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)
                .foregroundStyle(AppColors.headingColor)

            ActionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Search for a product", systemImage: "magnifyingglass")
                        .font(.headline)
                    
                    HStack(spacing: 10) {
                        TextField("What are you looking for?", text: $quickQuery)
                            .id("quickQueryField")
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .focused($isQuickQueryFocused)
                            .onSubmit {
                                isQuickQueryFocused = false      // סוגר מקלדת
                                dismissKeyboard()
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
                        if ocr.isProcessingOCR {
                            ProgressView()
                        }
                    }
                    
                    Text("Take or select a photo of an aisle sign and the app will detect and add the aisle.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            guard selectedStore != nil else { return }
                            
                            if Auth.auth().currentUser == nil ||
                                (Auth.auth().currentUser?.isAnonymous ?? true) {
                                showLoginRequiredAlert = true
                                return
                            }
                            
                            if showDemoUploadChooser {
                                showDemoUploadSheet = true
                            } else {
                                showPhotoSourceDialog = true
                            }
                        } label: {
                            Text("Upload image")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(ocr.isProcessingOCR)
                        
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
    }
    
    private var devLinksSection: some View {
        Group {
            if let store = selectedStore {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tools")
                        .font(.headline)
                        .foregroundStyle(AppColors.headingColor)

#if DEBUG
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Debug")
                            .font(.headline)

                        Button {
                            callOpenAIOcrProxyDebug()
                        } label: {
                            HStack {
                                Label("Call openaiOcrProxy (OCR demo_aisle_1)", systemImage: "text.viewfinder")
                                Spacer()
                                if isCallingFunction {
                                    ProgressView()
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCallingFunction)
                        
                        Button {
                            callOpenAIProxyDebug()
                        } label: {
                            HStack {
                                Label("Call openaiProxy", systemImage: "bolt.horizontal.circle")
                                Spacer()
                                if isCallingFunction {
                                    ProgressView()
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCallingFunction)

                        if !debugFunctionOutput.isEmpty {
                            ScrollView {
                                Text(debugFunctionOutput)
                                    .font(.system(.footnote, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .background(.thinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .frame(maxHeight: 220)
                        }
                    }
                    .padding(.top, 6)
#endif
                    HStack(spacing: 10) {
                        NavigationLink {
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

    // MARK: - Help / Tips
    
    private struct HelpTip: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
        let accent: String
    }
    
    private var helpTips: [HelpTip] {
        [
            HelpTip(
                icon: "location",
                title: "Location permission",
                body: "• Tap \"Allow location\" for the best experience\n• If you pick \"Only Once\", you can tap \"Refresh location\" later\n• If permission is denied, use \"Add manually\"",
                accent: "Location"
            ),
            HelpTip(
                icon: "hand.tap",
                title: "You can use the app without location",
                body: "• Choose a store manually\n• Or pick a previously selected store\n• You can still search products and manage aisles",
                accent: "Manual"
            ),
            HelpTip(
                icon: "cart",
                title: "What this app does",
                body: "Type a product (e.g. \"milk\") and get the aisle(s) where it should be — even if the exact word is not written in the aisle description.",
                accent: "Search"
            ),
            HelpTip(
                icon: "camera.viewfinder",
                title: "Add an aisle",
                body: "After choosing a store:\n• Upload an aisle-sign photo and the app will detect the aisle\n• Or add an aisle manually\n• Then add keywords / product descriptions for that aisle",
                accent: "OCR"
            ),
            HelpTip(
                icon: "person.badge.key",
                title: "Login is required to edit",
                body: "• You can browse and search without signing in\n• To upload images or update shared data, sign in with Google or Apple",
                accent: "Auth"
            ),
            HelpTip(
                icon: "shared.with.you",
                title: "Shared community data",
                body: "Store and aisle data is shared. When you add or improve info, other users can benefit too.",
                accent: "Shared"
            ),
            HelpTip(
                icon: "exclamationmark.bubble",
                title: "Reporting & change tracking",
                body: "If someone misuses the data, you can report it. Deletions and edits are tracked to keep things clean.",
                accent: "Safety"
            )
        ]
    }
    
    private var filteredHelpTips: [HelpTip] {
        let q = helpFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return helpTips }
        return helpTips.filter { tip in
            tip.title.localizedCaseInsensitiveContains(q) ||
            tip.body.localizedCaseInsensitiveContains(q)
        }
    }

    private struct DemoUploadSheet: View {
        let onPickDemoImageNamed: (String) -> Void
        let onDontShowAgain: () -> Void
        let onGotIt: () -> Void

        private let demoNames = ["demo_aisle_1", "demo_aisle_2", "demo_aisle_3"]
        @Environment(\.dismiss) private var dismiss    // ← מתווסף

        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Try a demo picture")
                        .font(.headline)
                        .foregroundStyle(AppColors.headingColor)

                    Text("Pick a sample aisle sign photo, or press Got it to use your own photo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(demoNames, id: \.self) { name in
                            Button {
                                onPickDemoImageNamed(name)
                            } label: {
                                DemoThumb(name: name)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(spacing: 12) {
                        // Row 1: Got it centered (below thumbnails)
                        HStack {
                            Spacer()
                            Button("Got it") { onGotIt() }
                                .buttonStyle(.borderedProminent)
                            Spacer()
                        }

                        Spacer()
                        
                        // Row 2: Don’t show again centered (last line)
                        HStack {
                            Spacer()
                            Button("Don’t show again") { onDontShowAgain() }
                                .buttonStyle(.bordered)
                            Spacer()
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(16)
                .navigationTitle("Upload image")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()  // סוגר את ה־sheet
                        }
                    }
                }
            }
        }

        private struct DemoThumb: View {
            let name: String

            var body: some View {
                ZStack {
                    if let ui = UIImage(named: name) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        // fallback if asset missing (instead of “some symbol”)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(
                                VStack(spacing: 6) {
                                    Image(systemName: "photo")
                                        .font(.title3)
                                    Text("Missing")
                                        .font(.caption2)
                                }
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .frame(width: 110, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    private struct HelpTipCard: View {
        let tip: HelpTip
        
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: tip.icon)
                        .font(.title3)
                    
                    Text(tip.title)
                        .font(.headline)
                    
                    Spacer()
                }
                
                Text(tip.body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                
                Spacer(minLength: 0)
                
                HStack {
                    Text(tip.accent)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                    
                    Spacer()
                }
            }
            .padding(14)
            .frame(width: 300, height: 170)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func aisleCount(for store: Store) -> Int {
        let storeUUID = store.id
        let descriptor = FetchDescriptor<Aisle>(
            predicate: #Predicate { $0.storeId == storeUUID }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    @MainActor
    private func deleteStoreEverywhere(_ store: Store) async {
        // 1. Firebase (אם יש remoteId)
        if let storeRemoteId = store.remoteId {
            do {
                try await firebase.deleteStore(storeRemoteId: storeRemoteId)
            } catch {
                print("❌ Failed to delete store in Firebase:", error)
                showBanner("Failed to delete store in cloud", isError: true)
                return
            }
        }
        
        // 2. Local delete (cascade deletes aisles/products)
        context.delete(store)
        do {
            try context.save()
        } catch {
            print("❌ Failed to delete store locally:", error)
            showBanner("Failed to delete store locally", isError: true)
        }
    }
    
    @MainActor
    private func stopAislesSync() {
        firebase.stopAislesListener()
        firebase.stopProductsListener()
        print("🛑 Stopped aisles & products listeners")
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

        firebase.startProductsListener(storeRemoteId: storeRemoteId, localStoreId: store.id, context: context)

        print("✅ Started aisles & products listeners for storeRemoteId:", storeRemoteId)
    }
    
    @MainActor
    private func ensureStoreRemoteId(_ store: Store) async {
        if store.remoteId != nil { return }
        
        // ✅ guard against double calls in parallel
        if ensuringStoreRemoteId.contains(store.id) { return }
        ensuringStoreRemoteId.insert(store.id)
        defer { ensuringStoreRemoteId.remove(store.id) }
        
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

#if DEBUG
    @MainActor
    private func callOpenAIOcrProxyDebug() {
        isCallingFunction = true
        debugFunctionOutput = ""

        // 1) Load demo image from assets
        guard let img = UIImage(named: "demo_aisle_1") else {
            isCallingFunction = false
            debugFunctionOutput = "❌ Missing demo image asset: demo_aisle_1"
            showBanner("Missing demo image", isError: true)
            return
        }

        // 2) Encode to JPEG → base64
        guard let jpeg = img.jpegData(compressionQuality: 0.85) else {
            isCallingFunction = false
            debugFunctionOutput = "❌ Failed to encode demo_aisle_1 as JPEG"
            showBanner("JPEG encode failed", isError: true)
            return
        }

        let base64 = jpeg.base64EncodedString()

        // 3) Build payload for openaiOcrProxy
        let payload: [String: Any] = [
            "model": "gpt-5.2",
            "image": [
                "mime": "image/jpeg",
                "base64": base64,
                "detail": "high"
            ]
        ]

        Task { @MainActor in
            do {
                _ = try await ensureFirebaseUser()

                functions.httpsCallable("openaiOcrProxy").call(payload) { result, error in
                    Task { @MainActor in
                        isCallingFunction = false

                        if let nsError = error as NSError? {
                            var lines: [String] = []
                            lines.append("❌ openaiOcrProxy error")
                            lines.append("localizedDescription: \(nsError.localizedDescription)")
                            lines.append("domain: \(nsError.domain)")
                            lines.append("code: \(nsError.code)")
                            lines.append("userInfo: \(nsError.userInfo)")

                            if let details = nsError.userInfo["details"] {
                                lines.append("details: \(details)")
                            }

                            debugFunctionOutput = lines.joined(separator: "\n")
                            showBanner("openaiOcrProxy failed", isError: true)
                            return
                        }

                        guard let data = result?.data else {
                            debugFunctionOutput = "⚠️ openaiOcrProxy returned nil data"
                            showBanner("openaiOcrProxy returned nil", isError: true)
                            return
                        }

                        // Prefer showing OCR text if present
                        if let dict = data as? [String: Any] {
                            let ok = dict["ok"] as? Bool
                            let text = dict["text"] as? String
                            let linesArr = dict["lines"] as? [String]
                            let lang = dict["language"] as? String

                            var out: [String] = []
                            out.append("✅ openaiOcrProxy success")
                            out.append("ok: \(ok == true ? "true" : "false")")
                            if let lang { out.append("language: \(lang)") }

                            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                out.append("\n--- OCR TEXT ---\n\(text)")
                            } else if let linesArr, !linesArr.isEmpty {
                                out.append("\n--- OCR LINES ---")
                                out.append(linesArr.joined(separator: "\n"))
                            } else {
                                out.append("\n⚠️ No OCR text returned.")
                            }

                            debugFunctionOutput = out.joined(separator: "\n")
                        } else {
                            // Fallback pretty print
                            debugFunctionOutput = prettyString(from: data)
                        }

                        showBanner("openaiOcrProxy success", isError: false)
                    }
                }
            } catch {
                isCallingFunction = false
                debugFunctionOutput = "❌ Auth failed: \(error.localizedDescription)"
                showBanner("Auth failed", isError: true)
            }
        }
    }

    @MainActor
    private func callOpenAIProxyDebug() {
        isCallingFunction = true
        debugFunctionOutput = ""

        let payload: [String: Any] = [
            "prompt": "Say hello in one short sentence.",
            "model": "gpt-4.1-mini",
            "temperature": 0.2
        ]

        Task { @MainActor in
            do {
                _ = try await ensureFirebaseUser()

                functions.httpsCallable("openaiProxy").call(payload) { result, error in
                    Task { @MainActor in
                        isCallingFunction = false

                        if let nsError = error as NSError? {
                            var lines: [String] = []
                            lines.append("❌ openaiProxy error")
                            lines.append("localizedDescription: \(nsError.localizedDescription)")
                            lines.append("domain: \(nsError.domain)")
                            lines.append("code: \(nsError.code)")
                            lines.append("userInfo: \(nsError.userInfo)")

                            if let details = nsError.userInfo["details"] {
                                lines.append("details: \(details)")
                            }

                            debugFunctionOutput = lines.joined(separator: "\n")
                            showBanner("openaiProxy failed", isError: true)
                            return
                        }

                        guard let data = result?.data else {
                            debugFunctionOutput = "⚠️ openaiProxy returned nil data"
                            showBanner("openaiProxy returned nil", isError: true)
                            return
                        }

                        debugFunctionOutput = prettyString(from: data)
                        showBanner("openaiProxy success", isError: false)
                    }
                }
            } catch {
                isCallingFunction = false
                debugFunctionOutput = "❌ Auth failed: \(error.localizedDescription)"
                showBanner("Auth failed", isError: true)
            }
        }
    }

    private func prettyString(from any: Any) -> String {
        // Try JSON pretty print first
        if JSONSerialization.isValidJSONObject(any),
           let data = try? JSONSerialization.data(withJSONObject: any, options: [.prettyPrinted]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }

        // If it's already a dictionary/array but not valid JSON, fall back
        return String(describing: any)
    }
#endif

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
        
        let fb = firebase   // ✅ capture EnvironmentObject value (not the wrapper)

        ocr.processImage(
            image,
            store: store,
            context: context,
            functions: functions,
            onBanner: { text, isError in
                showBanner(text, isError: isError)
            },
            onAisleCreated: { newId in
                pendingAisleToSelectID = newId
                goToAisles = true
            },
            onSyncToFirebase: { aisle in
                Task { @MainActor in
                    await fb.syncCreatedAisleToFirebase(aisle, store: store, context: context) { msg in
                        showBanner(msg, isError: true)
                    }
                }
            },
            firebase: firebase  // ← הוספת פרמטר
        )
        
//        ocr.processImage(
//            image,
//            store: store,
//            context: context,
//            visionService: visionService,
//            onBanner: { text, isError in
//                showBanner(text, isError: isError)
//            },
//            onAisleCreated: { newId in
//                pendingAisleToSelectID = newId
//                goToAisles = true
//            },
//            onSyncToFirebase: { aisle in
//                Task { @MainActor in
//                    await fb.syncCreatedAisleToFirebase(
//                        aisle,
//                        store: store,
//                        context: context
//                    ) { msg in
//                        showBanner(msg, isError: true)
//                    }
//                }
//            }
//        )
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
}

private struct ReportUserSheet: View {
    enum Reason: String, CaseIterable, Identifiable {
        case vandalism = "Vandalism / bad edits"
        case spam = "Spam"
        case harassment = "Harassment"
        case impersonation = "Impersonation"
        case other = "Other"
        var id: String { rawValue }
    }
    
    let title: String
    let onCancel: () -> Void
    let onSubmit: (_ reason: String?, _ details: String) -> Void
    
    @State private var selectedReason: Reason? = nil
    @State private var details: String = ""
    @State private var showValidationError: Bool = false
    
    private var trimmedDetails: String {
        details.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Rule: reason optional, BUT if no reason -> details required
    private var canSubmit: Bool {
        if selectedReason != nil { return true }
        return !trimmedDetails.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Reason (optional)")) {
                    Picker("Reason", selection: Binding(
                        get: { selectedReason },
                        set: { selectedReason = $0 }
                    )) {
                        Text("No reason selected").tag(Reason?.none)
                        ForEach(Reason.allCases) { r in
                            Text(r.rawValue).tag(Reason?.some(r))
                        }
                    }
                }
                
                Section(header: Text("More details")) {
                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                    
                    Text("If you don’t choose a reason, you must write something here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                if showValidationError {
                    Section {
                        Text("Please choose a reason or write details.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        if !canSubmit {
                            showValidationError = true
                            return
                        }
                        onSubmit(selectedReason?.rawValue, trimmedDetails)
                    }
                }
            }
        }
    }
}

private struct SelectedStoreGuideCard: View {
    let aisleCount: Int
    let onGotIt: () -> Void
    let onDontShowAgain: () -> Void

    private var recommendation: String {
        switch aisleCount {
            case 0...3:
                return "Start by pressing **Upload image** to add aisle signs."
            case 4...10:
                return "Press **Open aisle map** (or **Lines**) to verify all aisles were saved."
            default:
                return "Press **Search** and search for a product (e.g. milk, rice)."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What you can do here")
                        .font(.headline)

                    Text(
                        "You can search products in the aisles, upload or take a picture of an aisle sign, or add aisles manually using **Open aisle map**."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Text(recommendation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button("Don’t show again") { onDontShowAgain() }
                    .buttonStyle(.bordered)

                Button("Got it") { onGotIt() }
                    .buttonStyle(.borderedProminent)

                Spacer()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ChooseStoreGuideCard: View {
    let showEnableLocationHint: Bool
    let onGotIt: () -> Void
    let onDontShowAgain: () -> Void

    private var bodyText: String {
        if showEnableLocationHint {
            return "To find stores near you, first tap the 📍 button below (**Allow location**). Then tap 🔍 to search nearby stores. Or use “Add manually”."
        } else {
            return "First choose a store. Tap the 🔍 button below to find nearby stores, or use “Add manually”."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome 👋")
                        .font(.headline)

                    Text(bodyText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button("Don’t show again") { onDontShowAgain() }
                    .buttonStyle(.bordered)

                Button("Got it") { onGotIt() }
                    .buttonStyle(.borderedProminent)

                Spacer()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

