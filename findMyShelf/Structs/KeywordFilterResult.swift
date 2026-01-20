struct KeywordFilterResult: Decodable {
    let kept: [String]          // רק keywords שנשארו
    let removed: [String]       // מה הוסר (לא חובה אבל עוזר לדיבאג)
    let language: String?       // "he"/"de"/"fr"... אם הצליח
}
