//import Foundation
//
//struct AisleVisionResult: Decodable {
//    let aisle_code: String?
//    let title_original: String?
//    let title_en: String?
//
//    let lines_original: [String]?
//    let lines_en: [String]?
//
//    let keywords_original: [String]?
//    let keywords_en: [String]?
//
//    let language: String?
//}
//
//struct NormalizedAisleVisionResult {
//    let aisle_code: String?
//    let title_original: String?
//    let title_en: String?
//    let lines_original: [String]
//    let lines_en: [String]
//    let keywords_original: [String]
//    let keywords_en: [String]
//    let language: String?
//}
//
//final class OpenAIAisleVisionService {
//
//    private let apiKey: String
//    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
//
//    init(apiKey: String) {
//        self.apiKey = apiKey
//    }
//
//    //    func analyzeAisle(imageJPEGData: Data) async throws -> AisleVisionResult {
//    func analyzeAisle(imageJPEGData: Data) async throws -> NormalizedAisleVisionResult {
//
//        let base64 = imageJPEGData.base64EncodedString()
//
////        let systemText = """
////You analyze supermarket aisle sign photos.
////Return ONLY valid JSON matching the schema.
////
////Critical rule:
////- First, transcribe the sign EXACTLY as separate text lines (lines_original), preserving each printed line as ONE unit.
////- Do NOT split a single printed line into multiple categories.
////- Only split if the sign clearly uses separators: bullets, columns, divider lines, or large spacing indicating separate items.
////- Keywords must be derived from the transcribed lines: usually 1 keyword phrase per line (a whole phrase, not single words).
////"""
//
//        let systemText = """
//You analyze supermarket aisle sign photos.
//Return ONLY valid JSON matching the schema.
//
//Hard rules:
//1) First extract the exact visible text as separate printed lines into lines_original.
//2) keywords_original MUST be in the same language/script as the sign and MUST be based on lines_original.
//   - Prefer copying whole lines (trimmed) as keyword phrases.
//   - Do NOT translate in keywords_original.
//3) lines_en is the English translation of lines_original (same order).
//4) keywords_en is the English translation of keywords_original (same order, same count).
//5) If you cannot confidently read original text, return empty arrays for BOTH original and English (do not guess).
//"""
//
////        let systemText = """
////You analyze supermarket aisle sign photos.
////Return ONLY valid JSON matching the schema.
////
////Hard rules:
////1) First extract the exact visible text as separate printed lines into lines_original.
////2) keywords_original MUST be based on lines_original and MUST be in the same language/script as the sign.
////   - Prefer copying the full line text (trimmed) as a single keyword phrase.
////   - Do NOT translate in keywords_original.
////3) keywords_en MUST be an English translation of keywords_original (same order, 1-to-1 mapping).
////4) If you cannot confidently read a line, omit it (do not guess).
////5) If keywords_original is empty, keywords_en must also be empty.
////6) If lines_original is empty, lines_en must also be empty.
////"""
//
////        let userText = """
////Return:
////- aisle_code: the aisle identifier exactly as seen or null
////- title_original: the main category line (usually the largest/most prominent) or null
////- title_en: English translation of title_original or null
////- lines_original: all category lines as seen on the sign, one array item per printed line
////- lines_en: English translation for each item in lines_original (same order)
////- keywords_original: 3-12 category phrases based mainly on lines_original (prefer using the full line text as a phrase)
////- keywords_en: English translations corresponding to keywords_original
////- language: ISO 639-1 or null
////
////Do not invent categories not present on the sign. If unsure, return fewer items rather than splitting words incorrectly.
////"""
//
////        let userText = """
////Return:
////- aisle_code: aisle number/identifier exactly as seen (trimmed) or null
////- title_original: the main category line as seen (trimmed) or null
////- title_en: English translation of title_original (trimmed) or null
////- lines_original: all category lines as seen on the sign, one item per printed line, in reading order
////- lines_en: English translation for each item in lines_original (same order)
////- keywords_original: 3-12 phrases taken from lines_original (copy the original text; keep the original language/script)
////- keywords_en: English translations of keywords_original (same count and order)
////- language: ISO 639-1 if possible, else null
////
////If the sign is in Hebrew, keywords_original must be Hebrew.
////Do not return only English keywords.
////"""
//
//        let userText = """
//Return:
//- aisle_code: aisle number/identifier exactly as seen (trimmed) or null
//- title_original: short main title as seen (trimmed) or null
//- title_en: English translation of title_original (trimmed) or null
//- lines_original: all category lines as seen on the sign (one item per printed line)
//- lines_en: English translation for each item in lines_original (same order)
//- keywords_original: 3-12 phrases taken from lines_original (copy original text; keep original language/script)
//- keywords_en: English translations of keywords_original (same count and order)
//- language: ISO 639-1 if possible, else null
//"""
//
////        let schema: [String: Any] = [
////            "type": "object",
////            "additionalProperties": false,
////            "properties": [
////                "aisle_code": ["type": ["string","null"]],
////                "title_original": ["type": ["string","null"]],
////                "title_en": ["type": ["string","null"]],
////                "keywords_original": ["type": "array", "minItems": 0, "items": ["type": "string"]],
////                "keywords_en": ["type": "array", "minItems": 0, "items": ["type": "string"]],
////                "lines_original": ["type": "array", "minItems": 0, "items": ["type": "string"]],
////                "lines_en": ["type": "array", "minItems": 0, "items": ["type": "string"]],
////                "language": ["type": ["string","null"]]
////            ],
////            "required": ["aisle_code","title_original","title_en","lines_original","lines_en","keywords_original","keywords_en","language"]
////        ]
//
//        let schema: [String: Any] = [
//            "type": "object",
//            "additionalProperties": false,
//            "properties": [
//                "aisle_code": ["type": ["string","null"]],
//                "title_original": ["type": ["string","null"]],
//                "title_en": ["type": ["string","null"]],
//
//                "lines_original": ["type": "array", "items": ["type": "string"]],
//                "lines_en": ["type": "array", "items": ["type": "string"]],
//
//                "keywords_original": ["type": "array", "items": ["type": "string"]],
//                "keywords_en": ["type": "array", "items": ["type": "string"]],
//                "language": ["type": ["string","null"]]
//            ],
//            "required": [
//                "aisle_code","title_original","title_en",
//                "lines_original","lines_en",
//                "keywords_original","keywords_en",
//                "language"
//            ]
//        ]
//
//        let body: [String: Any] = [
////            "model": "gpt-4o-mini",   // אפשר להחליף למודל שאתה משתמש בו בפועל
//            "model": "gpt-5.2",   // אפשר להחליף למודל שאתה משתמש בו בפועל
//            "temperature": 0.0,
//            "messages": [
//                ["role": "system", "content": systemText],
//                ["role": "user",
//                 "content": [
//                    ["type": "text", "text": userText],
//                    ["type": "image_url",
//                     "image_url": ["url": "data:image/jpeg;base64,\(base64)",
//                                   "detail": "high"]
//                    ]
//                 ]
//                ]
//            ],
//            "response_format": [
//                "type": "json_schema",
//                "json_schema": [
//                    "name": "aisle_vision_result",
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
//            throw NSError(domain: "OpenAIAisleVisionService", code: 1, userInfo: ["raw": raw])
//        }
//
//        // Chat Completions -> choices[0].message.content (JSON string)
//        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
//        let choices = root?["choices"] as? [[String: Any]]
//        let message = choices?.first?["message"] as? [String: Any]
//        let content = message?["content"] as? String ?? "{}"
//
//        // 1) decode
//        let decoded = try JSONDecoder().decode(AisleVisionResult.self, from: Data(content.utf8))
//
//        // 2) post-fix / normalize
//        func clean(_ arr: [String]?) -> [String] {
//            (arr ?? [])
//                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
//                .filter { !$0.isEmpty }
//        }
//
////        let linesO = clean(decoded.lines_original)
////        let linesE = clean(decoded.lines_en)
////        var kwO = clean(decoded.keywords_original)
////        var kwE = clean(decoded.keywords_en)
////
////        if kwO.isEmpty && !kwE.isEmpty {
////            if !linesO.isEmpty {
////                kwO = Array(linesO.prefix(12))
////                if !linesE.isEmpty {
////                    kwE = Array(linesE.prefix(12))
////                } else {
////                    kwE = []
////                }
////            } else {
////                kwE = []
////            }
////        }
////
////        let kwCount = min(kwO.count, kwE.count)
////        if kwCount > 0 {
////            kwO = Array(kwO.prefix(kwCount))
////            kwE = Array(kwE.prefix(kwCount))
////        } else if !kwO.isEmpty || !kwE.isEmpty {
////            kwO = []
////            kwE = []
////        }
////
////        let linesCount = min(linesO.count, linesE.count)
////        let finalLinesO = linesCount > 0 ? Array(linesO.prefix(linesCount)) : linesO
////        let finalLinesE = linesCount > 0 ? Array(linesE.prefix(linesCount)) : linesE
//
//        let linesO_raw = clean(decoded.lines_original)
//        let linesE_raw = clean(decoded.lines_en)
//        var kwO = clean(decoded.keywords_original)
//        var kwE = clean(decoded.keywords_en)
//
//        // ---- lines: חייבים להיות 1:1. אם אחד ריק -> שניהם ריקים
//        let linesCount = min(linesO_raw.count, linesE_raw.count)
//        let finalLinesO = linesCount > 0 ? Array(linesO_raw.prefix(linesCount)) : []
//        let finalLinesE = linesCount > 0 ? Array(linesE_raw.prefix(linesCount)) : []
//
//        // ---- keywords: חייבים להיות 1:1. אם המודל החזיר רק אנגלית -> ננסה לבנות מה-lines
//        if kwO.isEmpty && !kwE.isEmpty {
//            // אם אין lines זוגיים - לא ננחש
//            if !finalLinesO.isEmpty && !finalLinesE.isEmpty {
//                let k = min(12, finalLinesO.count, finalLinesE.count)
//                kwO = Array(finalLinesO.prefix(k))
//                kwE = Array(finalLinesE.prefix(k))
//            } else {
//                kwO = []
//                kwE = []
//            }
//        }
//
//        // ---- enforce same count
//        let kwCount = min(kwO.count, kwE.count)
//        if kwCount > 0 {
//            kwO = Array(kwO.prefix(kwCount))
//            kwE = Array(kwE.prefix(kwCount))
//        } else {
//            kwO = []
//            kwE = []
//        }
//
//        // 3) return normalized (Option A / recommended)
////        return NormalizedAisleVisionResult(
////            aisle_code: decoded.aisle_code,
////            title_original: decoded.title_original?.trimmingCharacters(in: .whitespacesAndNewlines),
////            title_en: decoded.title_en?.trimmingCharacters(in: .whitespacesAndNewlines),
////            lines_original: finalLinesO,
////            lines_en: finalLinesE,
////            keywords_original: kwO,
////            keywords_en: kwE,
////            language: decoded.language
////        )
//
//        return NormalizedAisleVisionResult(
//            aisle_code: decoded.aisle_code,
//            title_original: decoded.title_original?.trimmingCharacters(in: .whitespacesAndNewlines),
//            title_en: decoded.title_en?.trimmingCharacters(in: .whitespacesAndNewlines),
//            lines_original: finalLinesO,
//            lines_en: finalLinesE,
//            keywords_original: kwO,
//            keywords_en: kwE,
//            language: decoded.language
//        )
//
//
////        return try JSONDecoder().decode(AisleVisionResult.self, from: Data(content.utf8))
//    }
//}
