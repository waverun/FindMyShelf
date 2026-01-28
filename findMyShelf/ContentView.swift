import SwiftUI
import FirebaseAuth
import SwiftData
import CoreLocation
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var firebase: FirebaseService   // ✅ add
    
    
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
    @State private var isHelpExpanded: Bool = true
    
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
                
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
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
            
            // ✅ Help / Tips (fills empty space on first screen)
            //            helpTipsSection
            
            HelpTipsSection(
                filterText: $helpFilterText,
                isExpanded: $isHelpExpanded
            )
            
            if !finder.results.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(finder.results.prefix(12).enumerated()), id: \.element.id) { index, store in
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
                .padding(.bottom, 6)
                // Keep the tips visible even when there are no results
                // (already shown above, but this adds a clear visual anchor)
                Divider().padding(.vertical, 4)
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
                        if ocr.isProcessingOCR {
                            ProgressView()
                        }
                    }
                    
                    Text("Take or select a photo of an aisle sign and the app will detect and add the aisle.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        guard selectedStore != nil else { return }
                        
                        if Auth.auth().currentUser == nil {
                            showLoginRequiredAlert = true
                            return
                        }
                        
                        showPhotoSourceDialog = true
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
    
    private var devLinksSection: some View {
        Group {
            if let store = selectedStore {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tools")
                        .font(.headline)
                    
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
    
    // MARK: - Logic
    
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
    
    //    private var helpTipsSection: some View {
    //        VStack(alignment: .leading, spacing: 10) {
    //            HStack(alignment: .firstTextBaseline) {
    //                Text("Getting started")
    //                    .font(.headline)
    //
    //                Button(isHelpExpanded ? "Hide" : "Show") {
    //                    withAnimation(.easeInOut(duration: 0.18)) {
    //                        isHelpExpanded.toggle()
    //                    }
    //                }
    //                .font(.subheadline)
    //                .buttonStyle(.bordered)
    //
    //                Spacer()
    //            }
    //
    //            TextField("Search tips…", text: $helpFilterText)
    //                .textFieldStyle(.roundedBorder)
    //                .submitLabel(.done)
    //
    //            if isHelpExpanded {
    //                if filteredHelpTips.isEmpty {
    //                    EmptyStateCard(
    //                        title: "No matching tips",
    //                        subtitle: "Try a different keyword.",
    //                        icon: "magnifyingglass"
    //                    )
    //                } else {
    //                    ScrollView(.horizontal, showsIndicators: false) {
    //                        LazyHStack(spacing: 14) {
    //                            ForEach(filteredHelpTips) { tip in
    //                                HelpTipCard(tip: tip)
    //                            }
    //                        }
    //                        .padding(.vertical, 6)
    //                        .padding(.horizontal, 2)
    //                    }
    //                }
    //            }
    //        }
    //        .padding(.top, 6)
    //    }
    
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
            visionService: visionService,
            onBanner: { text, isError in
                showBanner(text, isError: isError)
            },
            onAisleCreated: { newId in
                pendingAisleToSelectID = newId
                goToAisles = true
            },
            onSyncToFirebase: { aisle in
                Task { @MainActor in
                    await fb.syncCreatedAisleToFirebase(
                        aisle,
                        store: store,
                        context: context
                    ) { msg in
                        showBanner(msg, isError: true)
                    }
                }
            }
        )
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
