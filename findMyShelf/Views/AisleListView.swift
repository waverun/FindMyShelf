import SwiftUI
import SwiftData
import PhotosUI

struct AisleListView: View {
    @Environment(\.modelContext) private var context

    let store: Store

    // כל השורות בבסיס הנתונים
    @Query(sort: \Aisle.createdAt, order: .forward)
    private var allAisles: [Aisle]

    @State private var newAisleName: String = ""

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

    var body: some View {
        VStack {
            List {
                ForEach(aislesForStore) { aisle in
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
                            }
                        }
                    }
                }
                .onDelete(perform: deleteAisles)
            }

            if let err = ocrErrorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

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
            // כפתור מצלמה
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isShowingCamera = true
                } label: {
                    Image(systemName: "camera")
                }
            }

            // כפתור גלריה (PhotosPicker)
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

    // MARK: - Actions בסיסיים (הוספה/מחיקה ידנית)

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

    private func deleteAisles(at offsets: IndexSet) {
        for index in offsets {
            let aisle = aislesForStore[index]
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

    private func processImage(_ image: UIImage) {
        ocrErrorMessage = nil
        isProcessingOCR = true

        AisleOCRService.extractAisleInfo(from: image) { result in
            self.isProcessingOCR = false

            guard let rawTitle = result.title,
                  !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.ocrErrorMessage = "לא זוהתה כותרת שורה מהשלט."
                return
            }

            let name = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            // מונעים כפילות בסיסית
            if self.aislesForStore.contains(where: { $0.nameOrNumber == name }) {
                self.ocrErrorMessage = "שורה '\(name)' כבר קיימת."
                return
            }

            let aisle = Aisle(
                nameOrNumber: name,
                storeId: self.store.id,
                keywords: result.keywords
            )

            self.context.insert(aisle)
            do {
                try self.context.save()
                self.ocrErrorMessage = nil
            } catch {
                print("Failed to save OCR aisle:", error)
                self.ocrErrorMessage = "שגיאה בשמירת השורה החדשה."
            }
        }
    }
}
