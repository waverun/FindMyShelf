import Foundation
final class OpenAIAisleVisionService {

    private let apiKey: String
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func analyzeAisle(imageJPEGData: Data) async throws -> AisleVisionResult {
        let base64 = imageJPEGData.base64EncodedString()

        let systemText = """
        You analyze supermarket aisle sign photos.
        Return ONLY valid JSON matching the schema.
        """

        let userText = """
Return:
- aisle_code: the aisle number/identifier exactly as seen (trimmed) or null
- title_original: short title as seen (trimmed)
- title_en: English translation (trimmed)
- keywords_original: 3-12 relevant keywords (lowercase if possible)
- keywords_en: 3-12 English keywords (lowercase)
- language: ISO 639-1 if you can (e.g., "he", "de", "fr"), else null
If unsure, use null for aisle_code/title fields and empty keyword arrays.
"""

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "aisle_code": ["type": ["string","null"]],
                "title_original": ["type": ["string","null"]],
                "title_en": ["type": ["string","null"]],
                "keywords_original": ["type": "array", "items": ["type": "string"]],
                "keywords_en": ["type": "array", "items": ["type": "string"]],
                "language": ["type": ["string","null"]]
            ],
            "required": ["aisle_code","title_original","title_en","keywords_original","keywords_en","language"]
        ]

        let body: [String: Any] = [
            "model": "gpt-4o-mini",   // אפשר להחליף למודל שאתה משתמש בו בפועל
//            "model": "gpt-5.2",   // אפשר להחליף למודל שאתה משתמש בו בפועל
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemText],
                ["role": "user",
                 "content": [
                    ["type": "text", "text": userText],
                    ["type": "image_url",
                     "image_url": ["url": "data:image/jpeg;base64,\(base64)",
                                   "detail": "high"]
                    ]
                 ]
                ]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "aisle_vision_result",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAIAisleVisionService", code: 1, userInfo: ["raw": raw])
        }

        // Chat Completions -> choices[0].message.content (JSON string)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = root?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? "{}"

        return try JSONDecoder().decode(AisleVisionResult.self, from: Data(content.utf8))
    }
}
