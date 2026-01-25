import Foundation
import SwiftData
import UIKit

@MainActor
final class AisleOCRController: ObservableObject {

    @Published var isProcessingOCR: Bool = false

    func processImage(
        _ image: UIImage,
        store: Store,
        context: ModelContext,
        visionService: OpenAIAisleVisionService,
        onBanner: @escaping (_ text: String, _ isError: Bool) -> Void,
        onAisleCreated: @escaping (_ newAisleId: UUID) -> Void,
        onSyncToFirebase: @escaping (_ aisle: Aisle) -> Void
    ) {
        isProcessingOCR = true

        Task {
            do {
                guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
                    throw NSError(domain: "Image", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG"])
                }

                let result = try await visionService.analyzeAisle(imageJPEGData: jpeg)

                isProcessingOCR = false

                let titleOriginal = (result.title_original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let titleEn = (result.title_en ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let aisleCode = (result.aisle_code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                let displayTitle =
                !aisleCode.isEmpty ? aisleCode :
                !titleEn.isEmpty ? titleEn :
                (!titleOriginal.isEmpty ? titleOriginal : "")

                guard !displayTitle.isEmpty else {
                    onBanner("No aisle title could be detected from the sign", true)
                    return
                }

                // keywords
                var all: [String] = []
                all.append(contentsOf: result.keywords_original)
                all.append(contentsOf: result.keywords_en)
                if !titleOriginal.isEmpty { all.append(titleOriginal) }
                if !titleEn.isEmpty { all.append(titleEn) }

                let normalized = all
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map { $0.lowercased() }

                let uniqueKeywords = Array(Set(normalized)).sorted()

                // prevent duplicates (local)
                let storeID = store.id
                let descriptor = FetchDescriptor<Aisle>(
                    predicate: #Predicate<Aisle> { aisle in
                        aisle.storeId == storeID
                    }
                )
                let aisles = (try? context.fetch(descriptor)) ?? []
                if aisles.contains(where: { $0.nameOrNumber == displayTitle }) {
                    onBanner("Aisle '\(displayTitle)' already exists", true)
                    return
                }

                // create aisle
                let aisle = Aisle(
                    nameOrNumber: displayTitle,
                    storeId: store.id,
                    keywords: uniqueKeywords
                )

                context.insert(aisle)
                do {
                    try context.save()
                    onBanner("Aisle added: \(displayTitle)", false)

                    onSyncToFirebase(aisle)          // Firebase sync stays outside controller
                    onAisleCreated(aisle.id)         // navigation stays outside controller
                } catch {
                    onBanner("Failed to save the new aisle", true)
                }

            } catch {
                isProcessingOCR = false
                onBanner("Failed to analyze image: \(error.localizedDescription)", true)
            }
        }
    }
}
