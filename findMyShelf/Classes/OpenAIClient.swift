import Foundation
import FirebaseFunctions

enum GPTTaskImportance {
    case low
    case medium
    case high
}

struct OpenAIError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class OpenAIClient {
    static let shared = OpenAIClient()

    // ✅ Call your Firebase callable function (region must match deploy: us-central1)
    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // You can map importance → model/temperature like before
    private func model(for importance: GPTTaskImportance) -> String {
        switch importance {
            case .low: return "gpt-4.1-mini"
            case .medium: return "gpt-4.1-mini"
            case .high: return "gpt-4.1-mini" // or upgrade if you want
        }
    }

    private func temperature(for importance: GPTTaskImportance) -> Double {
        switch importance {
            case .low: return 0.1
            case .medium: return 0.3
            case .high: return 0.2
        }
    }

    /// Calls Firebase callable `openaiProxy` which calls OpenAI server-side.
    /// Expects `openaiProxy` to return: { ok: Bool, text: String, ... }
    func sendJSONChatRequest<T: Decodable>(
        systemPrompt: String,
        userPrompt: String,
        importance: GPTTaskImportance,
        responseType: T.Type
    ) async throws -> T {

        // 1) Make the model return STRICT JSON only
        //    (Because your Cloud Function returns plain text in `text`)
        let combinedPrompt = """
        SYSTEM:
        \(systemPrompt)
        
        USER:
        \(userPrompt)
        
        IMPORTANT:
        Return ONLY a valid JSON object (no markdown, no explanation).
        """

        let payload: [String: Any] = [
            "prompt": combinedPrompt,
            "model": model(for: importance),
            "temperature": temperature(for: importance),
        ]

        // 2) Call Firebase callable using async/await
        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("openaiProxy").call(payload)
        } catch {
            throw OpenAIError(message: "Firebase callable failed: \(error.localizedDescription)")
        }

        // 3) Extract returned dictionary
        guard let dict = result.data as? [String: Any] else {
            throw OpenAIError(message: "openaiProxy returned non-dictionary data: \(result.data)")
        }

        // Optional: check ok flag
        if let ok = dict["ok"] as? Bool, ok == false {
            throw OpenAIError(message: "openaiProxy returned ok=false: \(dict)")
        }

        guard let text = dict["text"] as? String else {
            throw OpenAIError(message: "openaiProxy missing 'text': \(dict)")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAIError(message: "openaiProxy returned empty text")
        }

        // 4) Decode JSON text into T
        guard let contentData = trimmed.data(using: .utf8) else {
            throw OpenAIError(message: "Failed to convert text to UTF-8 data")
        }

        do {
            return try JSONDecoder().decode(T.self, from: contentData)
        } catch {
            // Helpful debug: include the raw JSON string
            throw OpenAIError(message: "Failed to decode JSON. Error: \(error)\nRaw:\n\(trimmed)")
        }
    }
}

//import Foundation
//
//enum GPTTaskImportance {
//    case low
//    case medium
//    case high
//}
//
//struct OpenAIError: Error {
//    let message: String
//}
//
//// ⬇️ להעביר החוצה מהפונקציה הג'נרית
//private struct ChatResponse: Decodable {
//    struct Choice: Decodable {
//        struct Message: Decodable {
//            let content: String
//        }
//        let message: Message
//    }
//    let choices: [Choice]
//}
//
//final class OpenAIClient {
//    static let shared = OpenAIClient()
//
////    private let apiKey: String = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
//    private var apiKey: String {
//        Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
//    }
//
//    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
//
//    private init() {}
//
//    private func model(for importance: GPTTaskImportance) -> String {
//        switch importance {
//            case .low: return "gpt-4o-mini"
//            case .medium: return "gpt-4o-mini"
//            case .high: return "gpt-4o"
//        }
//    }
//
//    private func temperature(for importance: GPTTaskImportance) -> Double {
//        switch importance {
//            case .low: return 0.1
//            case .medium: return 0.3
//            case .high: return 0.2
//        }
//    }
//
//    func sendJSONChatRequest<T: Decodable>(
//        systemPrompt: String,
//        userPrompt: String,
//        importance: GPTTaskImportance,
//        responseType: T.Type
//    ) async throws -> T {
//
//        guard !apiKey.isEmpty else {
//            throw OpenAIError(message: "Missing OPENAI_API_KEY environment variable.")
//        }
//
//        var request = URLRequest(url: baseURL)
//        request.httpMethod = "POST"
//        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
//
//        let body: [String: Any] = [
//            "model": model(for: importance),
//            "temperature": temperature(for: importance),
//            "response_format": ["type": "json_object"],
//            "messages": [
//                ["role": "system", "content": systemPrompt],
//                ["role": "user",   "content": userPrompt]
//            ]
//        ]
//
//        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
//
//        let (data, response) = try await URLSession.shared.data(for: request)
//
//        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
//            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
//            throw OpenAIError(message: "OpenAI API error: \(text)")
//        }
//
//        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
//
//        guard let contentData = chat.choices.first?.message.content.data(using: .utf8) else {
//            throw OpenAIError(message: "No content in OpenAI response.")
//        }
//
//        return try JSONDecoder().decode(T.self, from: contentData)
//    }
//}
