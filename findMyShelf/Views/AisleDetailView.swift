import SwiftUI
import SwiftData

struct AisleDetailView: View {
    @Environment(\.modelContext) private var context

    @Bindable var aisle: Aisle

    @State private var keywordsText: String

    init(aisle: Aisle) {
        self.aisle = aisle
        _keywordsText = State(initialValue: aisle.keywords.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section("שם / מספר שורה") {
                TextField("למשל: 12 או מוצרי חלב", text: $aisle.nameOrNumber)
                    .textInputAutocapitalization(.never)
            }

            Section("מילות מפתח") {
                TextField("מילים מופרדות בפסיקים או רווחים", text: $keywordsText)
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        applyKeywords()
                    }

                if !aisle.keywords.isEmpty {
                    Text("מילות המפתח שקיימות:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    WrapKeywordsView(keywords: aisle.keywords)
                } else {
                    Text("עוד אין מילות מפתח לשורה הזו.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("עריכת שורה")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("שמור") {
                    applyKeywords()
                    save()
                }
            }
        }
        .onDisappear {
            // ליתר ביטחון – ניסיון שמירה גם ביציאה
            applyKeywords()
            save()
        }
    }

    // מעדכן את aisle.keywords מתוך הטקסט
    private func applyKeywords() {
        let raw = keywordsText.lowercased()

        let parts = raw
            .replacingOccurrences(of: "，", with: ",")
            .split { $0 == "," || $0 == " " || $0 == ";" || $0 == "\n" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        aisle.keywords = Array(Set(parts))   // ייחודיות
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Failed to save aisle:", error)
        }
    }
}

struct WrapKeywordsView: View {
    let keywords: [String]

    var body: some View {
        LazyVGrid(
            columns: [
                // כל צ'יפ לפחות 120pt רוחב → 2–3 טורים במקום 5–6 צרים
                GridItem(.adaptive(minimum: 120), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(keywords, id: \.self) { kw in
                Text(kw)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                // מאפשר לשורה להיות טיפה גמישה, בלי לחנוק את הטקסט
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

/// Layout פשוט של Chips
struct FlexibleChips: View {
    let items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        VStack {
            GeometryReader { geo in
                self.generateContent(in: geo)
            }
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .alignmentGuide(.leading) { d in
                        if width + d.width > g.size.width {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        width += d.width
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        return result
                    }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        totalHeight = geo.size.height
                    }
                    .onChange(of: geo.size.height) { _, newHeight in
                        totalHeight = newHeight
                    }
            }
        )
    }
}
