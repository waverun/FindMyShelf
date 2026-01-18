import Foundation

struct GPTAisleSuggestionResponse: Codable {
    let candidates: [GPTAisleCandidate]
    let not_found: Bool
}

struct GPTAisleCandidate: Codable {
    let aisleId: String
    let confidence_label: String   // e.g. "sure", "likely", "maybe", "uncertain"
    let confidence_score: Double   // 0.0–1.0
    let reason: String
}
