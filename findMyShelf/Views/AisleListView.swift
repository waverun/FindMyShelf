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

    @State private var newAisleName: String = ""

    // חיפוש / פילטר
    @State private var filterText: String = ""

    // עבור PhotosPicker
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var isProcessingOCR: Bool = false
    @State private var ocrErrorMessage: String?

    // עבור מצלמה
    @State private var isShowingCamera: Bool = false

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
                let analysis = try await analyzer.analyze(image)

                await MainActor.run {
                    isProcessingOCR = false

                    let title = !analysis.titleEN.isEmpty ? analysis.titleEN : analysis.titleOriginal
                    guard !title.isEmpty else {
                        ocrErrorMessage = "לא הצלחתי לזהות כותרת מהשלט."
                        return
                    }

                    // בדיקת כפילות
                    if aislesForStore.contains(where: { $0.nameOrNumber == title }) {
                        ocrErrorMessage = "השורה '\(title)' כבר קיימת."
                        return
                    }

                    let aisle = Aisle(nameOrNumber: title, storeId: store.id, keywords: analysis.keywords)
                    context.insert(aisle)
                    do {
                        try context.save()
                    } catch {
                        ocrErrorMessage = "שמירה נכשלה."
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
        VStack {
            // שורת חיפוש
            HStack {
                TextField("חפש שורה או מילות מפתח…", text: $filterText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding([.horizontal, .top])

            // רשימת שורות (מסוננת)
            List {
                if filteredAisles.isEmpty {
                    Text("לא נמצאו שורות בהתאם לחיפוש.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredAisles) { aisle in
                        NavigationLink {
                            AisleDetailView(aisle: aisle)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("שורה \(aisle.nameOrNumber)")
                                    .font(.headline)
                                if !aisle.keywords.isEmpty {
                                    Text(aisle.keywords.joined(separator: ", "))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteAislesFiltered)
                }
            }

            if let err = ocrErrorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            // הוספה ידנית
            HStack {
                TextField("מספר/שם שורה חדש…", text: $newAisleName)
                    .textFieldStyle(.roundedBorder)

                Button("הוסף") {
                    addAisle()
                }
                .disabled(newAisleName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .navigationTitle("מיפוי שורות – \(store.name)")
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
                        Text("בחר שלט מהגלריה")
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
                    self.ocrErrorMessage = "לא הצלחתי לקרוא את התמונה מהגלריה."
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
