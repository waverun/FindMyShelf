import SwiftUI
import SwiftData
import PhotosUI

struct AisleListView: View {
    @Environment(\.modelContext) private var context

    private let analyzer = AisleImageAnalyzer()

    let store: Store

    // כל השורות בבסיס הנתונים
    @Query(sort: \Aisle.createdAt, order: .forward)
    private var allAisles: [Aisle]

    @State private var selectedAisleID: UUID?
    @State private var isEditingSelected: Bool = false
    @State private var isScrollingCards: Bool = false

    @State private var newAisleName: String = ""

    // חיפוש / פילטר
    @State private var filterText: String = ""

    // עבור PhotosPicker
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var isProcessingOCR: Bool = false
    @State private var ocrErrorMessage: String?

    // עבור מצלמה
    @State private var isShowingCamera: Bool = false

    @FocusState private var focusedField: FocusedField?

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
        allAisles.filter { $0.storeId == store.id }
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

    private func processImage(_ image: UIImage) {
        ocrErrorMessage = nil
        isProcessingOCR = true

        Task {
            do {
                guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
                    await MainActor.run {
                        isProcessingOCR = false
                        ocrErrorMessage = "I couldn't convert the image to JPEG."
                    }
                    return
                }

                // 1) Vision (async) — מחוץ ל-MainActor
                let result = try await visionService.analyzeAisle(imageJPEGData: jpeg)

                // 2) קביעת שם (sync) — מחוץ ל-MainActor
                let name = aisleNameFromVision(result)
                guard name != "Unknown" else {
                    await MainActor.run {
                        isProcessingOCR = false
                        ocrErrorMessage = "I couldn't detect an aisle number or title from the sign."
                    }
                    return
                }

                // 3) סינון Keywords (async) — מחוץ ל-MainActor
                let rawKeywords = (result.keywords_original ?? []) + (result.keywords_en ?? [])

                let finalKeywords = rawKeywords
                
                // 4) UI + SwiftData — בתוך MainActor
                await MainActor.run {
                    isProcessingOCR = false

                    if aislesForStore.contains(where: { $0.nameOrNumber == name }) {
                        ocrErrorMessage = "Aisle '\(name)' already exists."
                        return
                    }

                    let aisle = Aisle(nameOrNumber: name, storeId: store.id, keywords: finalKeywords)
                    context.insert(aisle)

                    do {
                        try context.save()
                    } catch {
                        ocrErrorMessage = "Save failed."
                    }
                }

            } catch {
                await MainActor.run {
                    isProcessingOCR = false
                    ocrErrorMessage = error.localizedDescription
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack {
                // שורת חיפוש
                HStack {
                    //                TextField("Search for an aisle or keywords…", text: $filterText)
                    //                    .textFieldStyle(.roundedBorder)
                    TextField("Search for an aisle or keywords…", text: $filterText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .filter)
                        .submitLabel(.search)
                }
                .padding([.horizontal, .top])

                // כרטיסיות שורות – אופקי
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
                                    // בחירה בלבד (לא עריכה)
                                    selectedAisleID = aisle.id
                                    isEditingSelected = false
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
                            isEditing: $isEditingSelected,
                            onDelete: {
                                context.delete(aisle)
                                try? context.save()
                                selectedAisleID = nil
                                isEditingSelected = false
                            },
                            onSave: { newName, newKeywords in
                                aisle.nameOrNumber = newName
                                aisle.keywords = newKeywords
                                try? context.save()
                                isEditingSelected = false
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.36), value: selectedAisleID)

                if let err = ocrErrorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

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

                    Button("הוסף") {
                        addAisle()
                    }
                    .disabled(newAisleName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Aisles map \(store.name)")
            .toolbar {
                // מצלמה
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Image(systemName: "camera")
                    }
                }

                // גלריה
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $pickedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        if isProcessingOCR {
                            ProgressView()
                        } else {
                            Text("Select signd from gallery")
                        }
                    }
                }
            }
            // מצלמה – sheet
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker(isPresented: $isShowingCamera) { image in
                    processImage(image)
                }
            }
            // גלריה – שינוי בפריט שנבחר
            .onChange(of: pickedPhotoItem) { _, newItem in
                if let item = newItem {
                    handlePickedPhoto(item)
                }
            }
            .contentShape(Rectangle())     // חשוב!
            .onTapGesture {
                focusedField = nil
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - פעולות בסיסיות

    private func addAisle() {
        let trimmed = newAisleName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let aisle = Aisle(nameOrNumber: trimmed, storeId: store.id)
        context.insert(aisle)
        do {
            try context.save()
            newAisleName = ""
        } catch {
            print("Failed to save aisle:", error)
        }
    }

    /// מחיקה מתוך filteredAisles – מוחק את האובייקט עצמו מהקונטקסט
    private func deleteAislesFiltered(at offsets: IndexSet) {
        for index in offsets {
            let aisle = filteredAisles[index]
            context.delete(aisle)
        }
        do {
            try context.save()
        } catch {
            print("Failed to delete aisles:", error)
        }
    }

    // MARK: - גלריה → UIImage

    private func handlePickedPhoto(_ item: PhotosPickerItem) {
        ocrErrorMessage = nil

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    self.ocrErrorMessage = "I couldn't load the image from the photo library."
                }
                return
            }
            await MainActor.run {
                self.processImage(image)
            }
        }
    }

    // MARK: - OCR משותף למצלמה ולגלריה

//    private let apiKey: String = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    private var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
    }

    private var visionService: OpenAIAisleVisionService {
        OpenAIAisleVisionService(apiKey: apiKey)
    }
}

private struct AisleCard: View {
    let title: String
    let keywords: [String]
    let colorIndex: Int
    let isSelected: Bool
    let onSelect: () -> Void

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
                        Text(keywords.prefix(6).joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                    } else {
                        Text("No keywords")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }

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
    @Binding var isEditing: Bool

    let onDelete: () -> Void
    let onSave: (_ newName: String, _ newKeywords: [String]) -> Void

    @State private var draftName: String = ""
    @State private var draftKeywordsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("Selected aisle")
                    .font(.headline)
                Spacer()

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

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete aisle", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

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
