//import Foundation
//
//final class OpenAIKeywordSanitizerService {
//    private let apiKey: String
//    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
//
//    init(apiKey: String) { self.apiKey = apiKey }
//
//    func filterProductKeywords(
//        originalKeywords: [String],
//        languageHint: String?
//    ) async throws -> KeywordFilterResult {
//
//        // אם אין כלום—לא צריך קריאה נוספת
//        if originalKeywords.isEmpty {
//            return KeywordFilterResult(kept: [], removed: [], language: languageHint)
//        }
//
//        let systemText = """
//        You clean OCR/vision keywords from supermarket aisle signs.
//        Keep ONLY words/phrases that are valid grocery product names or grocery categories.
//        Remove numbers, prices, discounts, units, marketing words, or codes.
//        Return ONLY valid JSON matching the schema.
//        """
//
//        let userText = """
//        Language hint: \(languageHint ?? "null")
//        
//        Input keywords (may contain noise):
//        \(originalKeywords)
//        
//        Rules:
//        - Keep only grocery product names or grocery categories a shopper would search for.
//        - Remove: pure numbers, percentages, currency, weights/units (g, kg, ml, l), sizes, dates, promo words (sale/new/offer), and aisle codes (A12).
//        - Normalize:
//          - Trim whitespace
//          - Keep original script (Hebrew stays Hebrew, etc.)
//          - Prefer lowercase where natural (English)
//        - Output: kept + removed.
//        """
//
//        let schema: [String: Any] = [
//            "type": "object",
//            "additionalProperties": false,
//            "properties": [
//                "kept": ["type": "array", "items": ["type": "string"]],
//                "removed": ["type": "array", "items": ["type": "string"]],
//                "language": ["type": ["string","null"]]
//            ],
//            "required": ["kept","removed","language"]
//        ]
//
//        let body: [String: Any] = [
//            "model": "gpt-4o-mini",
//            "temperature": 0,
//            "messages": [
//                ["role": "system", "content": systemText],
//                ["role": "user", "content": userText]
//            ],
//            "response_format": [
//                "type": "json_schema",
//                "json_schema": [
//                    "name": "keyword_filter_result",
//                    "strict": true,
//                    "schema": schema
//                ]
//            ]
//        ]
//
//        var req = URLRequest(url: endpoint)
//        req.httpMethod = "POST"
//        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
//        req.httpBody = try JSONSerialization.data(withJSONObject: body)
//
//        let (data, resp) = try await URLSession.shared.data(for: req)
//
//        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
//            let raw = String(data: data, encoding: .utf8) ?? ""
//            throw NSError(domain: "OpenAIKeywordSanitizerService", code: 1, userInfo: ["raw": raw])
//        }
//
//        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
//        let choices = root?["choices"] as? [[String: Any]]
//        let message = choices?.first?["message"] as? [String: Any]
//        let content = message?["content"] as? String ?? "{}"
//
//        return try JSONDecoder().decode(KeywordFilterResult.self, from: Data(content.utf8))
//    }
//}
