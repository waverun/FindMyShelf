import UIKit
import Vision

struct AisleOCRResult {
    let title: String?      // כותרת השורה (מספר/שם)
    let keywords: [String]  // מילות מפתח מהשלט
    let confidence: Double  // ציון אמון ממוצע 0–1
}

enum AisleOCRService {

    static func extractAisleInfo(from image: UIImage,
                                 completion: @escaping (AisleOCRResult) -> Void) {
        guard let cg = image.cgImage else {
            completion(AisleOCRResult(title: nil, keywords: [], confidence: 0))
            return
        }

        let request = VNRecognizeTextRequest { req, _ in
            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []

            var lines: [String] = []
            var confidences: [Float] = []

            for obs in observations {
                if let best = obs.topCandidates(1).first {
                    lines.append(best.string)
                    confidences.append(best.confidence)
                }
            }

            let fullText = lines.joined(separator: " ")

            // ניסיון למצוא מספר שורה (רצף ספרות)
            let digits = fullText
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .joined()
                .trimmingCharacters(in: .whitespaces)

            let title: String?
            if !digits.isEmpty {
                title = digits
            } else {
                title = fullText.isEmpty ? nil : fullText
            }

            // מילות מפתח – מחלקים לטוקנים, מסננים קצרות
            let keywords = fullText
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }

            let avgConf: Double
            if confidences.isEmpty {
                avgConf = 0
            } else {
                let sum = confidences.reduce(0, +)
                avgConf = Double(sum / Float(confidences.count))
            }

            let uniqueKeywords = Array(Set(keywords))

            let result = AisleOCRResult(
                title: title?.trimmingCharacters(in: .whitespacesAndNewlines),
                keywords: uniqueKeywords,
                confidence: avgConf
            )

            DispatchQueue.main.async {
                completion(result)
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["he", "en"]  // עברית + אנגלית

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("OCR error: \(error)")
            let fallback = AisleOCRResult(title: nil, keywords: [], confidence: 0)
            DispatchQueue.main.async {
                completion(fallback)
            }
        }
    }
}
