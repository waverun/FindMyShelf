import Foundation
import SwiftData

enum ProductGPTSuggestionError: Error {
    case noAisles
    case openAIError(String)
}

struct AisleSummaryForGPT: Codable {
    let id: String
    let nameOrNumber: String
    let keywords: [String]
}

/// פונקציה כללית יחסית: שולחת שם מוצר + שורות קיימות ל-GPT
/// ומקבלת עד 3 שורות מוצעות, לפי ביטחון.
func suggestAislesForProductUsingGPT(
    productName: String,
    aisles: [Aisle],
    importance: GPTTaskImportance = .medium,
    firebase: FirebaseService  // ← הוספת פרמטר
) async throws -> GPTAisleSuggestionResponse {

    guard !aisles.isEmpty else {
        throw ProductGPTSuggestionError.noAisles
    }

    // נכין רשימה "נקייה" לשליחה
    let summaries: [AisleSummaryForGPT] = aisles.map {
        AisleSummaryForGPT(
            id: $0.id.uuidString,
            nameOrNumber: $0.nameOrNumber,
            keywords: $0.keywords
        )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    let aislesJSON = String(data: try encoder.encode(summaries), encoding: .utf8) ?? "[]"

    let systemPrompt = """
    You are an assistant that maps grocery products to store aisles.
    You receive:
    1. A product name.
    2. A list of aisles, each with: id, nameOrNumber, keywords (like the text on the aisle sign).
    
    Your task:
    - Guess which aisle(s) are the best matches for the product.
    - Return up to 3 candidates sorted from best to worst.
    - If no aisle fits reasonably, mark not_found = true and candidates = [].
    
    Confidence:
    - Use these labels: "sure", "likely", "maybe", "uncertain".
    - confidence_score must be a number between 0.0 and 1.0.
    - "sure" ≈ >= 0.85, "likely" ≈ 0.7–0.85, "maybe" ≈ 0.4–0.7, "uncertain" < 0.4.
    
    Output MUST be a single JSON object exactly in this schema:
    {
      "candidates": [
        {
          "aisleId": "<string (one of the aisle ids I give you)>",
          "confidence_label": "<sure|likely|maybe|uncertain>",
          "confidence_score": <number 0.0–1.0>,
          "reason": "<short explanation in English>"
        }
      ],
      "not_found": <true|false>
    }
    """

    let userPrompt = """
    Product: "\(productName)"
    
    Aisles JSON:
    \(aislesJSON)
    """

    do {
        let response: GPTAisleSuggestionResponse = try await OpenAIClient.shared.sendJSONChatRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            importance: importance,
            responseType: GPTAisleSuggestionResponse.self
        )
        return response
    } catch let error as OpenAIError {
        // רישום בפיירבייס
        await firebase.logApiError(
            endpoint: "OpenAI.sendJSONChatRequest",
            message: error.localizedDescription,
            additionalData: ["product": productName]
        )
        throw ProductGPTSuggestionError.openAIError(error.message)
    } catch {
        await firebase.logApiError(
            endpoint: "OpenAI.sendJSONChatRequest",
            message: error.localizedDescription,
            additionalData: ["product": productName]
        )
        throw ProductGPTSuggestionError.openAIError(error.localizedDescription)
    }
}
