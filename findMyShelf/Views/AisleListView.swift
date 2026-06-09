import SwiftUI
import FirebaseAuth
import SwiftData
//import PhotosUI

enum UploadSourceRequest: Equatable {
    case camera
    case photoLibrary
}

final class UploadFlowCoordinator: ObservableObject {
    @Published var requestUpload: Bool = false
    @Published var requestedUploadSource: UploadSourceRequest? = nil
    @Published var postUploadBannerMessage: String? = nil
}

struct AisleListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var uploadFlow: UploadFlowCoordinator
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var firebase: FirebaseService
    
    let store: Store
    let initialSelectedAisleID: UUID?   // ✅ add this

    @AppStorage("showAisleMapGuideCard") private var showAisleMapGuideCard: Bool = true

    @State private var didSeeAisleMapGuide: Bool = false

    @State private var isLoggedIn: Bool = Auth.auth().currentUser != nil && !(Auth.auth().currentUser?.isAnonymous ?? true)

    @State private var isNewAisleSelection: Bool = false
    
    // כל השורות בבסיס הנתונים
    @Query(sort: \Aisle.createdAt, order: .forward)
    private var allAisles: [Aisle]
    
    @State private var selectedAisleID: UUID?
    @State private var isEditingSelected: Bool = false
    
    @State private var newAisleName: String = ""
    
    // חיפוש / פילטר
    @State private var filterText: String = ""
    
    @FocusState private var focusedField: FocusedField?
    
    // Login gating (same alert text/buttons as ContentView)
    @State private var showLoginRequiredAlert = false
    @State private var loginAppleCoordinator = AppleSignInCoordinator()

    @State private var bannerText: String?
    @State private var bannerIsError: Bool = false
    @State private var showUploadReward: Bool = false
    @State private var uploadRewardTrigger: Int = 0
    
    private enum FocusedField: Hashable {
        case newAisleName
        case filter
    }
    
    private var selectedAisle: Aisle? {
        guard let id = selectedAisleID else { return nil }
        return aislesForStore.first(where: { $0.id == id })
    }
    
    // שורות רק של החנות הזו
    private var aislesForStore: [Aisle] {
        allAisles
            .filter { $0.storeId == store.id }
            .sorted {
                $0.nameOrNumber.localizedStandardCompare($1.nameOrNumber) == .orderedAscending
            }
    }
    
    // שורות אחרי פילטר
    private var filteredAisles: [Aisle] {
        let text = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else {
            return aislesForStore
        }
        return aislesForStore.filter { aisle in
            let nameHit = aisle.nameOrNumber.lowercased().contains(text)
            let keywordHit = aisle.keywords.contains { kw in
                kw.lowercased().contains(text)
            }
            return nameHit || keywordHit
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack {
                if showAisleMapGuideCard && !didSeeAisleMapGuide {
                    AisleMapGuideCard(
                        onGotIt: {
                            didSeeAisleMapGuide = true
                        },
                        onDontShowAgain: {
                            showAisleMapGuideCard = false
                            didSeeAisleMapGuide = true
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                // שורת חיפוש
                HStack {
                    TextField("Search for an aisle or keywords…", text: $filterText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .filter)
                        .submitLabel(.search)
                }
                .padding([.horizontal, .top])
                
                // כרטיסיות שורות – אופקי
                
                // כרטיסיות שורות – אופקי
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            if filteredAisles.isEmpty {
                                Text("No aisles were found matching your search.")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            } else {
                                ForEach(Array(filteredAisles.enumerated()), id: \.element.id) { index, aisle in
                                    AisleCard(
                                        title: aisle.nameOrNumber,
                                        keywords: aisle.keywords,
                                        colorIndex: index,
                                        isSelected: aisle.id == selectedAisleID
                                    ) {
                                        selectedAisleID = aisle.id
                                        isEditingSelected = false
                                        isNewAisleSelection = false
                                        
                                        // ✅ אופציונלי: גם כשבוחרים ידנית, לגלול למרכז
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            proxy.scrollTo(aisle.id, anchor: .center)
                                        }
                                    }
                                    .id(aisle.id) // ✅ חובה בשביל scrollTo
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        // ✅ אם נכנסנו עם שורה לבחור – גלול אליה
                        isLoggedIn = Auth.auth().currentUser != nil && !(Auth.auth().currentUser?.isAnonymous ?? true)
                        _ = Auth.auth().addStateDidChangeListener { _, user in
                            isLoggedIn = (user != nil)
                            if user == nil {
                                // אם המשתמש התנתק בזמן עריכה – לצאת מעריכה
                                isEditingSelected = false
                            }
                        }
                        
                        if let id = selectedAisleID {
                            DispatchQueue.main.async {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedAisleID) { _, newId in
                        guard let newId else { return }
                        // ✅ אם השורה משתנה (כולל זו שהגיעה מהמסך הקודם)
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { _ in
                            focusedField = nil
                            guard selectedAisleID != nil else { return }
                            withAnimation(.easeInOut(duration: 0.36)) {
                                selectedAisleID = nil
                                isEditingSelected = false
                            }
                        }
                )
                
                // פאנל למטה
                Group {
                    if let aisle = selectedAisle {
                        AisleBottomPanel(
                            aisle: aisle,
                            headerTitle: isNewAisleSelection ? "New aisle" : "Selected aisle",
                            canEdit: isLoggedIn,
                            isEditing: $isEditingSelected,
                            onDelete: {
                                Task { @MainActor in
                                    await deleteAisleEverywhere(aisle)
                                    selectedAisleID = nil
                                    isEditingSelected = false
                                }
                            },
                            onSave: { newName, newKeywords in
                                Task { @MainActor in
                                    aisle.nameOrNumber = newName
                                    aisle.keywords = newKeywords
                                    aisle.updatedAt = Date()
                                    
                                    do {
                                        try context.save()
                                    } catch {
                                        print("❌ Failed to save aisle locally:", error)
                                        return
                                    }
                                    
                                    // Sync to Firebase only if we can
                                    guard let storeRemoteId = store.remoteId,
                                          aisle.remoteId != nil else {
                                        isEditingSelected = false
                                        return
                                    }
                                    
                                    do {
                                        try await firebase.updateAisle(storeRemoteId: storeRemoteId, aisle: aisle)
                                    } catch {
                                        print("❌ Failed to update aisle in Firebase:", error)
                                        // Optional: keep editing open or show banner
                                    }
                                    
                                    isEditingSelected = false
                                }
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.36), value: selectedAisleID)
                
                // הוספה ידנית
                HStack {
                    //                TextField("...number / new asile name", text: $newAisleName)
                    //                    .textFieldStyle(.roundedBorder)
                    
                    TextField("...number / new aisle name", text: $newAisleName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .newAisleName)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil   // סוגר מקלדת
                                                 // אופציונלי: להוסיף שורה אוטומטית
                                                 // addAisle()
                        }
                    
                    Button {
                        let trimmed = newAisleName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        
                        // If not logged in, prompt login (do not block typing in the field)
                        if Auth.auth().currentUser == nil ||
                            (Auth.auth().currentUser?.isAnonymous ?? true) {
                            showLoginRequiredAlert = true
                            return
                        }
                        
                        addAisle()
                    } label: {
                        Text("Add aisle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(newAisleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()

                }
                .contentShape(Rectangle())     // חשוב!
                .onTapGesture {
                    focusedField = nil
                }
            }

            if let bannerText {
                BannerView(
                    text: bannerText,
                    isError: bannerIsError,
                    actionTitle: nil,
                    onAction: nil,
                    onTap: nil,
                    onClose: {
                        withAnimation { self.bannerText = nil }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }

            if showUploadReward {
                UploadRewardView(trigger: uploadRewardTrigger, reduceMotion: reduceMotion)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .navigationTitle("Aisles map \(store.name)")
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                uploadSourceButton(title: "Take photo", systemImage: "camera.viewfinder") {
                    uploadFlow.requestedUploadSource = .camera
                    dismiss()
                }

                uploadSourceButton(title: "Library", systemImage: "photo.on.rectangle") {
                    uploadFlow.requestedUploadSource = .photoLibrary
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(.regularMaterial)
        }
        .onAppear {
            if let id = initialSelectedAisleID {
                selectedAisleID = id
                isEditingSelected = false
                isNewAisleSelection = true
            }
            if let msg = uploadFlow.postUploadBannerMessage {
                showBanner(msg, isError: false)
                playUploadReward()
                uploadFlow.postUploadBannerMessage = nil
            }
        }
        .onChange(of: uploadFlow.postUploadBannerMessage) { _, newValue in
            guard let msg = newValue else { return }
            showBanner(msg, isError: false)
            uploadFlow.postUploadBannerMessage = nil
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
    }
    
    private func uploadSourceButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func showBanner(_ text: String, isError: Bool) {
        bannerIsError = isError
        withAnimation {
            bannerText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            withAnimation {
                if bannerText == text {
                    bannerText = nil
                }
            }
        }
    }

    private func playUploadReward() {
        uploadRewardTrigger += 1
        withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
            showUploadReward = true
        }

        let trigger = uploadRewardTrigger
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            guard uploadRewardTrigger == trigger else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                showUploadReward = false
            }
        }
    }

    // MARK: - פעולות בסיסיות
    
    @MainActor
    private func deleteAisleEverywhere(_ aisle: Aisle) async {
        // If we can delete in Firebase, do it first
        if let storeRemoteId = store.remoteId, let aisleRemoteId = aisle.remoteId {
            do {
                try await firebase.deleteAisle(storeRemoteId: storeRemoteId, aisleRemoteId: aisleRemoteId)
            } catch {
                // If Firebase delete failed, do NOT delete locally (keeps consistency)
                print("❌ Failed to delete aisle in Firebase:", error)
                return
            }
        }
        
        // Always delete locally (also covers "not synced yet" aisles)
        context.delete(aisle)
        do {
            try context.save()
        } catch {
            print("❌ Failed to delete aisle locally:", error)
        }
    }
    
    @MainActor
    private func addAisle() {
        let trimmed = newAisleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // 1) create locally first (fast UI)
        let aisle = Aisle(nameOrNumber: trimmed, storeId: store.id, keywords: [])
        context.insert(aisle)
        
        do {
            try context.save()
            newAisleName = ""
            focusedField = nil
            selectedAisleID = aisle.id
            isEditingSelected = false
            isNewAisleSelection = true
        } catch {
            print("❌ Failed to save aisle locally:", error)
            return
        }
        
        // 2) then sync to Firebase (if store is synced)
        guard let storeRemoteId = store.remoteId else {
            print("⚠️ Store has no remoteId yet, aisle stays local-only for now.")
            return
        }
        
        Task { @MainActor in
            do {
                let rid = try await firebase.createAisle(storeRemoteId: storeRemoteId, aisle: aisle)
                aisle.remoteId = rid
                aisle.updatedAt = Date()
                try? context.save()
            } catch {
                print("❌ Failed to create aisle in Firebase:", error)
                // optional: you can show a banner or mark unsynced state
            }
        }
    }
}

private struct AisleCard: View {
    let title: String
    let keywords: [String]
    let colorIndex: Int
    let isSelected: Bool
    let onSelect: () -> Void

    private func bidiWrap(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // LRM before + after helps neutral punctuation stay put
        return "\u{200E}" + t + "\u{200E}"
    }

    var body: some View {
        let base = color(for: colorIndex)
        
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        colors: [base.opacity(0.95), base.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(isSelected ? .white.opacity(0.9) : .white.opacity(0.18),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(radius: isSelected ? 16 : 12, y: isSelected ? 8 : 6)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aisle \(title)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !keywords.isEmpty {
                        ScrollView(.vertical, showsIndicators: true) {
                            let text = keywords.map(bidiWrap).joined(separator: ", ")
                            Text(text)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.trailing, 6) // קצת מקום לאינדיקטור
                        }
                        .frame(maxHeight: 44) // ⬅️ קובע "חלון" גלילה. אפשר 52/60 לפי הטעם
                        .scrollClipDisabled()  // iOS 17+: לא חותך shadow של האינדיקטור (אופציונלי)
                    } else {
                        Text("No keywords")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }
//                    if !keywords.isEmpty {
//                        let text = keywords.map(bidiWrap).joined(separator: ", ")
//                        Text(text)
//                            .font(.footnote)
//                            .foregroundStyle(.white.opacity(0.85))
//                    } else {
//                        Text("No keywords")
//                            .font(.footnote)
//                            .foregroundStyle(.white.opacity(0.8))
//                    }

                    Spacer()

                    Text(isSelected ? "Selected" : "Tap to select")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
                .padding(16)
            }
            .frame(width: 280, height: 160)
        }
        .buttonStyle(.plain)
    }
    
    private func color(for index: Int) -> Color {
        let palette: [Color] = [.blue, .purple, .indigo, .teal, .mint, .pink, .orange]
        return palette[index % palette.count]
    }
}

private struct AisleBottomPanel: View {
    @Bindable var aisle: Aisle
    let headerTitle: String          // ✅ new
    let canEdit: Bool
    @Binding var isEditing: Bool
    
    let onDelete: () -> Void
    let onSave: (_ newName: String, _ newKeywords: [String]) -> Void
    
    @State private var showDeleteConfirm = false
    
    @State private var draftName: String = ""
    @State private var draftKeywordsText: String = ""
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    //                Text("Selected aisle")
                    Text(headerTitle)
                        .font(.headline)
                    Spacer()
                    if canEdit {
                        if isEditing {
                            Button("Done") {
                                let kws = draftKeywordsText
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                                onSave(draftName.trimmingCharacters(in: .whitespacesAndNewlines), kws)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Edit") {
                                draftName = aisle.nameOrNumber
                                draftKeywordsText = aisle.keywords.joined(separator: ", ")
                                isEditing = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                if !isEditing {
                    Text("Aisle \(aisle.nameOrNumber)")
                        .font(.title3.bold())
                    
                    if !aisle.keywords.isEmpty {
                        Text("Keywords: \(aisle.keywords.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No keywords yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    
                    // 🗑️ Trash icon
                    //                    if !isEditing {
                    if canEdit && !isEditing {
                        HStack {
                            Spacer()
                            
                            Button {
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .padding(10)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                    )
                            }
                            .padding(10)
                            .confirmationDialog(
                                "Delete this aisle?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible
                            ) {
                                Button("Delete", role: .destructive) {
                                    onDelete()
                                }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text("This action cannot be undone.")
                            }
                        }
                    }
                } else {
                    TextField("Aisle name/number", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Keywords (comma separated)", text: $draftKeywordsText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                    
                    HStack {
                        Button(role: .destructive) {
                            isEditing = false
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            let kws = draftKeywordsText
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            onSave(draftName.trimmingCharacters(in: .whitespacesAndNewlines), kws)
                        } label: {
                            Text("Save")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
            )
        }
    }
}

private struct UploadRewardView: View {
    let trigger: Int
    let reduceMotion: Bool

    @State private var animate: Bool = false
    @State private var ringRotation: Double = -60

    private static let sparkleOffsets: [CGSize] = [
        CGSize(width: -96, height: -70),
        CGSize(width: 0, height: -96),
        CGSize(width: 92, height: -64),
        CGSize(width: -112, height: 8),
        CGSize(width: 112, height: 16),
        CGSize(width: -78, height: 82),
        CGSize(width: 4, height: 104),
        CGSize(width: 82, height: 76)
    ]

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(Array(Self.sparkleOffsets.enumerated()), id: \.offset) { index, offset in
                    Image(systemName: index.isMultiple(of: 2) ? "sparkles" : "star.fill")
                        .font(.system(size: index.isMultiple(of: 3) ? 18 : 13, weight: .bold))
                        .foregroundStyle(index.isMultiple(of: 2) ? AppColors.logoOrangeLight : .yellow)
                        .scaleEffect(animate ? 1.0 : 0.2)
                        .opacity(animate ? 0.0 : 0.95)
                        .offset(animate ? offset : .zero)
                        .animation(.easeOut(duration: 1.0).delay(Double(index) * 0.04), value: animate)
                }
            }

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [AppColors.logoOrangeLight, AppColors.logoOrangeDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 88, height: 88)
                        .shadow(color: AppColors.logoOrangeDark.opacity(0.35), radius: 18, y: 10)

                    Circle()
                        .trim(from: 0.08, to: animate ? 1.0 : 0.18)
                        .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(reduceMotion ? -60 : ringRotation))

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(animate ? 1.0 : 0.68)
                }

                VStack(spacing: 3) {
                    Text("Aisle added")
                        .font(.title3.bold())
                    Text("+1 photo helped this store")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(animate && !reduceMotion ? 1.0 : 0.9)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aisle added. One photo helped this store.")
        .onAppear(perform: startAnimation)
        .onChange(of: trigger) { _, _ in
            startAnimation()
        }
    }

    private func startAnimation() {
        animate = false
        ringRotation = -60

        DispatchQueue.main.async {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.64)) {
                animate = true
            }

            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 3.2)) {
                ringRotation = 1020
            }
        }
    }
}

private struct AisleMapGuideCard: View {
    let onGotIt: () -> Void
    let onDontShowAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 6) {
                    Text("How to use the aisle map")
                        .font(.headline)

                    Text(
                        "• Search by aisle number/name (e.g. “3”, “Dairy”) or by **keywords** (types of products on the aisle).\n" +
                        "• To add an aisle: enter the aisle number/name and press **Add aisle**.\n" +
                        "• Afterwards you can add keywords in **any language** (English or not)."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                }

                Spacer()
            }

            // same style/behavior as before
            HStack(spacing: 10) {
                Button("Don’t show again") { onDontShowAgain() }
                    .buttonStyle(.bordered)

                Spacer()

                Button("Got it") { onGotIt() }
                    .buttonStyle(.borderedProminent)
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
