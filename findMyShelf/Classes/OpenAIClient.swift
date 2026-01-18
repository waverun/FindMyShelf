import Foundation

enum GPTTaskImportance {
    case low
    case medium
    case high
}

struct OpenAIError: Error {
    let message: String
}

// ⬇️ להעביר החוצה מהפונקציה הג'נרית
private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

final class OpenAIClient {
    static let shared = OpenAIClient()

    private let apiKey: String = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    private init() {}

    private func model(for importance: GPTTaskImportance) -> String {
        switch importance {
            case .low: return "gpt-4o-mini"
            case .medium: return "gpt-4o-mini"
            case .high: return "gpt-4o"
        }
    }

    private func temperature(for importance: GPTTaskImportance) -> Double {
        switch importance {
            case .low: return 0.1
            case .medium: return 0.3
            case .high: return 0.2
        }
    }

    func sendJSONChatRequest<T: Decodable>(
        systemPrompt: String,
        userPrompt: String,
        importance: GPTTaskImportance,
        responseType: T.Type
    ) async throws -> T {

        guard !apiKey.isEmpty else {
            throw OpenAIError(message: "Missing OPENAI_API_KEY environment variable.")
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model(for: importance),
            "temperature": temperature(for: importance),
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userPrompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError(message: "OpenAI API error: \(text)")
        }

        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let contentData = chat.choices.first?.message.content.data(using: .utf8) else {
            throw OpenAIError(message: "No content in OpenAI response.")
        }

        return try JSONDecoder().decode(T.self, from: contentData)
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
//final class OpenAIClient {
//    static let shared = OpenAIClient()
//
//    /// אל תשים מפתח בקוד. עדיף במשתני סביבה / Keychain / Config.
//    private let apiKey: String = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
//    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
//
//    private init() {}
//
//    private func model(for importance: GPTTaskImportance) -> String {
//        switch importance {
//            case .low:
//                return "gpt-4o-mini"      // זול, מהיר
//            case .medium:
//                return "gpt-4o-mini"      // אפשר להשאיר אותו
//            case .high:
//                return "gpt-4o"           // מדויק/חזק יותר
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
//    /// פונקציה כללית: שולחים system + user, מצפים ש־assistant יחזיר JSON שמתאים ל־T.
//    func sendJSONChatRequest<T: Decodable>(
//        systemPrompt: String,
//        userPrompt: String,
//        importance: GPTTaskImportance,
//        responseType: T.Type
//    ) async throws -> T {
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
//        // תבנית תשובת chat.completions
//        struct ChatResponse: Decodable {
//            struct Choice: Decodable {
//                struct Message: Decodable {
//                    let content: String
//                }
//                let message: Message
//            }
//            let choices: [Choice]
//        }
//
//        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
//        guard let content = chat.choices.first?.message.content.data(using: .utf8) else {
//            throw OpenAIError(message: "No content in OpenAI response.")
//        }
//
//        return try JSONDecoder().decode(T.self, from: content)
//    }
//}
