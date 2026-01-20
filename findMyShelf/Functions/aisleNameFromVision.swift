 func aisleNameFromVision(_ r: AisleVisionResult) -> String {
    let code = (r.aisle_code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !code.isEmpty { return code } // ONLY if detected

    let t1 = (r.title_original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !t1.isEmpty { return t1 }

    let t2 = (r.title_en ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !t2.isEmpty { return t2 }

    return "Unknown"
}
