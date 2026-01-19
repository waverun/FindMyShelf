import SwiftUI
import SwiftData

struct AisleDetailView: View {
    @Environment(\.modelContext) private var context

    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case keywords
    }

    @Bindable var aisle: Aisle

    @State private var keywordsText: String

    init(aisle: Aisle) {
        self.aisle = aisle
        _keywordsText = State(initialValue: aisle.keywords.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section("Name / Line number") {
                TextField("For example: 12 or dairy products", text: $aisle.nameOrNumber)
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .name)
                    .focused($focusedField, equals: .name)
            }

            Section("Keywords") {
                TextField("Words separated by commas or spaces", text: $keywordsText)
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .name)
                    .onSubmit {
                        applyKeywords()
                    }

                if !aisle.keywords.isEmpty {
                    Text("Existing keywords")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    WrapKeywordsView(keywords: aisle.keywords)
                } else {
                    Text("There are no keywords for this aisle yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onTapGesture { focusedField = nil }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Aisle editing")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    applyKeywords()
                    save()
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
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
        TagLayout(spacing: 6, lineSpacing: 6) {
            ForEach(keywords, id: \.self) { kw in
                Text(kw)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .fixedSize() // שלא יכווץ את המילה יותר מדי
            }
        }
        .padding(.top, 4)
    }
}

/// Layout שעושה wrap כמו תגיות: ממלא שורה, גולש לשורה הבאה.
struct TagLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        guard maxWidth < .infinity else {
            // אם אין רוחב מוגדר, נניח איזשהו רוחב סביר
            return arrange(in: 300, subviews: subviews).size
        }
        return arrange(in: maxWidth, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let arrangement = arrange(in: bounds.width, subviews: subviews)
        for (index, frame) in arrangement.frames.enumerated() {
            guard index < subviews.count else { break }
            let subview = subviews[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX,
                            y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    // חישוב מיקום וגודל כולל של כל התגיות
    private func arrange(in maxWidth: CGFloat,
                         subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []

        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // אם לא נכנס בשורה, יורדים שורה
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            frames.append(frame)

            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let totalHeight = y + lineHeight
        return (frames, CGSize(width: maxWidth, height: totalHeight))
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
