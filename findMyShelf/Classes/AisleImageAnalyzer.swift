import Foundation
import UIKit

struct AisleAnalysis {
    let titleOriginal: String
    let titleEN: String
    let keywords: [String]   // מאוחד: מקור+אנגלית
}

final class AisleImageAnalyzer {

    private let apiKey: String
    private let service: OpenAIAisleVisionService

    init(apiKey: String? = nil) {
        let keyFromPlist = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
        let finalKey = apiKey ?? keyFromPlist

        self.apiKey = finalKey
        self.service = OpenAIAisleVisionService(apiKey: finalKey)
    }
    
    func analyze(_ image: UIImage) async throws -> AisleAnalysis {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "Config", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "OPENAI_API_KEY is missing"])
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "Image", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG"])
        }

        let r = try await service.analyzeAisle(imageJPEGData: jpeg)

        let orig = (r.title_original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let en = (r.title_en ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var all: [String] = []
        all.append(contentsOf: r.keywords_original ?? [])
        all.append(contentsOf: r.keywords_en ?? [])
        if !orig.isEmpty { all.append(orig) }
        if !en.isEmpty { all.append(en) }

        let keywords = Array(Set(all
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        )).sorted()

        return AisleAnalysis(titleOriginal: orig, titleEN: en, keywords: keywords)
    }
}
