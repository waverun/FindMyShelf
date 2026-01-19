import Foundation

//struct AisleVisionResult: Decodable {
//    let title: String?
//    let keywords: [String]?
//}

struct AisleVisionResult: Decodable {
    let title_original: String?
    let title_en: String?
    let keywords_original: [String]?
    let keywords_en: [String]?
    let language: String?        // optional: e.g. "he", "de", "fr"
}

final class GPTAisleVisionService {

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func analyze(imageJPEGData: Data) async throws -> AisleVisionResult {
        let base64 = imageJPEGData.base64EncodedString()

        let prompt = """
        You are analyzing a photo of a supermarket aisle sign.
        Return ONLY valid JSON with fields:
        - title: short aisle title in English (translate if needed)
        - keywords: 3-10 simple lowercase keywords relevant to the aisle
        If you cannot determine a title, use title=null and keywords=[].
        """

        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "temperature": 0.2,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                    ]
                ]
            ],
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "GPTAisleVisionService", code: 1, userInfo: [
                "response": String(data: data, encoding: .utf8) ?? ""
            ])
        }

        // Parse Chat Completions response -> extract message content (JSON string)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? "{}"

        return try JSONDecoder().decode(AisleVisionResult.self, from: Data(content.utf8))
    }
}
