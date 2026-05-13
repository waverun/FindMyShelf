import Foundation
import SwiftData
import UIKit
import FirebaseFunctions

@MainActor
final class AisleOCRController: ObservableObject {

    @Published var isProcessingOCR: Bool = false

    private func sanitizeKeywords(_ raw: [String]) -> [String] {
        raw
            .map { collapseWhitespace($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { s in
                // Count Unicode letters (works for Hebrew/Arabic/Latin/etc.)
                let letterCount = s.unicodeScalars.reduce(into: 0) { acc, scalar in
                    if CharacterSet.letters.contains(scalar) { acc += 1 }
                }

                // Must contain at least 3 letters total
                return letterCount >= 3
            }
    }

    private func collapseWhitespace(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func keywordDedupKey(_ s: String) -> String {
        let punctuationAndSymbols = CharacterSet.punctuationCharacters.union(.symbols)
        let scalarView = s.unicodeScalars.map { scalar -> String in
            punctuationAndSymbols.contains(scalar) ? " " : String(scalar)
        }
        let withoutPunctuation = scalarView.joined()
        let collapsed = collapseWhitespace(withoutPunctuation)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return collapsed.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    private func dedupeKeywordsPreservingOrder(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for keyword in keywords {
            let key = keywordDedupKey(keyword)
            guard !key.isEmpty else { continue }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(keyword)
        }

        return out
    }

    func processImage(
        _ image: UIImage,
        store: Store,
        context: ModelContext,
        functions: Functions,
        onBanner: @escaping (_ text: String, _ isError: Bool) -> Void,
        onAisleCreated: @escaping (_ newAisleId: UUID) -> Void,
        onSyncToFirebase: @escaping (_ aisle: Aisle) -> Void,
        firebase: FirebaseService  // ← הוספת פרמטר
    ) {
        isProcessingOCR = true

        Task {
            do {
                guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
                    throw NSError(domain: "Image", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to encode JPEG"
                    ])
                }

                // ✅ ensure user exists (anonymous is fine)
                _ = try await ensureFirebaseUser(timeoutSeconds: 8)

                // ✅ call Cloud Function instead of OpenAI API
                let result = try await callAisleVisionProxy(
                    functions: functions,
                    jpegData: jpeg
                )

                isProcessingOCR = false

                let titleOriginal = (result.title_original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let titleEn = (result.title_en ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let aisleCode = (result.aisle_code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                let displayTitle =
                !aisleCode.isEmpty ? aisleCode :
                !titleEn.isEmpty ? titleEn :
                (!titleOriginal.isEmpty ? titleOriginal : "")

                // בונים את כל המילים מראש
                var allKeywords: [String] = []
                allKeywords.append(contentsOf: result.keywords_original)
                allKeywords.append(contentsOf: result.keywords_en)
                if !titleOriginal.isEmpty { allKeywords.append(titleOriginal) }
                if !titleEn.isEmpty { allKeywords.append(titleEn) }
                let cleaned = sanitizeKeywords(allKeywords)

                guard !displayTitle.isEmpty else {
                    await firebase.logApiError(
                        endpoint: "AisleOCR.processImage",
                        message: "No aisle title could be detected…",
                        additionalData: [
                            "storeId": store.id.uuidString,
                            "keywords": cleaned
                        ]
                    )
                    onBanner("No aisle title could be detected from the sign", true)
                    return
                }

//                // keywords
//                var all: [String] = []
//                all.append(contentsOf: result.keywords_original)
//                all.append(contentsOf: result.keywords_en)
//                if !titleOriginal.isEmpty { all.append(titleOriginal) }
//                if !titleEn.isEmpty { all.append(titleEn) }
//
//                // ✅ filter keywords BEFORE creating the aisle
//                let cleaned = sanitizeKeywords(all)

//                let uniqueKeywords = Array(
//                    Set(cleaned.map { $0.lowercased() })
//                ).sorted()

                // דה-דופליקציה קשיחה כדי למנוע כפילויות שנובעות מפיסוק/רווחים/Case
                let uniqueKeywords = dedupeKeywordsPreservingOrder(cleaned)

                // prevent duplicates (local) - if exists, merge keywords and open aisles screen
                let storeID = store.id
                let descriptor = FetchDescriptor<Aisle>(
                    predicate: #Predicate<Aisle> { aisle in
                        aisle.storeId == storeID
                    }
                )
                let aisles = (try? context.fetch(descriptor)) ?? []

                let normalizedDisplayTitle = displayTitle
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                if let existing = aisles.first(where: {
                    $0.nameOrNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedDisplayTitle
                }) {
                    let existingDeduped = dedupeKeywordsPreservingOrder(existing.keywords)
                    let mergedDeduped = dedupeKeywordsPreservingOrder(existingDeduped + uniqueKeywords)
                    let addedCount = max(0, mergedDeduped.count - existingDeduped.count)

                    existing.keywords = mergedDeduped
                    existing.updatedAt = Date()

                    do {
                        try context.save()
                        if addedCount == 0 {
                            onBanner("Aisle '\(existing.nameOrNumber)' already exists (no new keywords)", false)
                        } else {
                            onBanner("Merged \(addedCount) new keyword(s) into aisle '\(existing.nameOrNumber)'", false)
                        }

                        onSyncToFirebase(existing)
                        onAisleCreated(existing.id)
                    } catch {
                        onBanner("Failed to merge into existing aisle", true)
                    }
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

                    onSyncToFirebase(aisle)
                    onAisleCreated(aisle.id)
                } catch {
                    onBanner("Failed to save the new aisle", true)
                }

            } catch {
                await firebase.logApiError(
                    endpoint: "AisleOCR.processImage",
                    message: error.localizedDescription,
                    additionalData: ["storeId": store.id.uuidString]
                )
                isProcessingOCR = false
                onBanner("Failed to analyze image: \(error.localizedDescription)", true)
            }
        }
    }

    // MARK: - Callable wrapper

    private func callAisleVisionProxy(functions: Functions, jpegData: Data) async throws -> AisleVisionResult {
        let base64 = jpegData.base64EncodedString()

        let payload: [String: Any] = [
            "model": "gpt-5.2",
            "image": [
                "mime": "image/jpeg",
                "base64": base64,
                "detail": "high"
            ]
        ]

        return try await withCheckedThrowingContinuation { cont in
            functions.httpsCallable("openaiAisleVisionProxy").call(payload) { result, error in
                if let error { cont.resume(throwing: error); return }
                guard let data = result?.data else {
                    cont.resume(throwing: NSError(domain: "Cloud", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "openaiAisleVisionProxy returned nil data"
                    ]))
                    return
                }

                do {
                    // Allow either:
                    // 1) { result: {...} }  OR
                    // 2) { ...fields... }
                    let obj: Any
                    if let dict = data as? [String: Any], let inner = dict["result"] {
                        obj = inner
                    } else {
                        obj = data
                    }

                    let json = try JSONSerialization.data(withJSONObject: obj, options: [])
                    let decoded = try JSONDecoder().decode(AisleVisionResult.self, from: json)
                    print("decoded:", decoded)
                    cont.resume(returning: decoded)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

struct AisleVisionResult: Decodable {
    let title_original: String?
    let title_en: String?
    let aisle_code: String?
    let keywords_original: [String]
    let keywords_en: [String]
}

