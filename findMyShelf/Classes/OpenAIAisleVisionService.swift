import Foundation
final class OpenAIAisleVisionService {

    private let apiKey: String
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func analyzeAisle(imageJPEGData: Data) async throws -> AisleVisionResult {
        let base64 = imageJPEGData.base64EncodedString()

//        let systemText = """
//        You analyze supermarket aisle sign photos.
//        Return ONLY valid JSON matching the schema.
//        """

        let systemText = """
You analyze supermarket aisle sign photos.
Return ONLY valid JSON matching the schema.

Critical rule:
- First, transcribe the sign EXACTLY as separate text lines (lines_original), preserving each printed line as ONE unit.
- Do NOT split a single printed line into multiple categories.
- Only split if the sign clearly uses separators: bullets, columns, divider lines, or large spacing indicating separate items.
- Keywords must be derived from the transcribed lines: usually 1 keyword phrase per line (a whole phrase, not single words).
"""

//        let userText = """
//Return:
//- aisle_code: the aisle number/identifier exactly as seen (trimmed) or null
//- title_original: short title as seen (trimmed)
//- title_en: English translation (trimmed)
//- keywords_original: 3-12 relevant keywords (lowercase if possible)
//- keywords_en: 3-12 English keywords (lowercase)
//- language: ISO 639-1 if you can (e.g., "he", "de", "fr"), else null
//If unsure, use null for aisle_code/title fields and empty keyword arrays.
//"""

        let userText = """
Return:
- aisle_code: the aisle identifier exactly as seen or null
- title_original: the main category line (usually the largest/most prominent) or null
- title_en: English translation of title_original or null
- lines_original: all category lines as seen on the sign, one array item per printed line
- lines_en: English translation for each item in lines_original (same order)
- keywords_original: 3-12 category phrases based mainly on lines_original (prefer using the full line text as a phrase)
- keywords_en: English translations corresponding to keywords_original
- language: ISO 639-1 or null

Do not invent categories not present on the sign. If unsure, return fewer items rather than splitting words incorrectly.
"""

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
//            "properties": [
//                "aisle_code": ["type": ["string","null"]],
//                "title_original": ["type": ["string","null"]],
//                "title_en": ["type": ["string","null"]],
//                "keywords_original": ["type": "array", "items": ["type": "string"]],
//                "keywords_en": ["type": "array", "items": ["type": "string"]],
//                "language": ["type": ["string","null"]]
//            ],
//            "required": ["aisle_code","title_original","title_en","keywords_original","keywords_en","language"]
            "properties": [
                "aisle_code": ["type": ["string","null"]],
                "title_original": ["type": ["string","null"]],
                "title_en": ["type": ["string","null"]],

                "lines_original": ["type": "array", "items": ["type": "string"]],
                "lines_en": ["type": "array", "items": ["type": "string"]],

                "keywords_original": ["type": "array", "items": ["type": "string"]],
                "keywords_en": ["type": "array", "items": ["type": "string"]],
                "language": ["type": ["string","null"]]
            ],
            "required": ["aisle_code","title_original","title_en","lines_original","lines_en","keywords_original","keywords_en","language"]
        ]

        let body: [String: Any] = [
//            "model": "gpt-4o-mini",   // אפשר להחליף למודל שאתה משתמש בו בפועל
            "model": "gpt-5.2",   // אפשר להחליף למודל שאתה משתמש בו בפועל
            "temperature": 0.0,
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
