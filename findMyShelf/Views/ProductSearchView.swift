import SwiftUI
import SwiftData

struct ProductSearchView: View {
    @Environment(\.modelContext) private var context

    let store: Store

    @Query(sort: \Aisle.createdAt, order: .forward)
    private var allAisles: [Aisle]

    let initialQuery: String   // ✅ חדש

    @FocusState private var isProductQueryFocused: Bool

    @State private var didAutoSearch = false   // ✅ חדש

    @Query(sort: \ProductItem.createdAt, order: .forward)
    private var allProducts: [ProductItem]

    @State private var productQuery: String = ""
    @State private var statusMessage: String?
    @State private var suggestedAisle: Aisle?
    @State private var foundExistingProduct: ProductItem?

    @State private var isCallingGPT: Bool = false
    @State private var gptCandidates: [GPTAisleCandidate] = []

    // שורות ומוצרים רק לחנות הזו
    private var aislesForStore: [Aisle] {
        allAisles.filter { $0.storeId == store.id }
    }
    private var productsForStore: [ProductItem] {
        allProducts.filter { $0.storeId == store.id }
    }

    var body: some View {
        ZStack {
            Form {
                Section("Product Search") {
                    //                TextField("Type a product name…", text: $productQuery)
                    //                    .textInputAutocapitalization(.never)
                    //                    .onSubmit {
                    //                        runSearch()
                    //                    }

                    TextField("Type a product name…", text: $productQuery)
                        .textInputAutocapitalization(.never)
                        .focused($isProductQueryFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            isProductQueryFocused = false   // ✅ סוגר מקלדת
                            runSearch()
                        }

                    Button {
                        runSearch()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Find aisle", systemImage: "magnifyingglass")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                    .background(.thinMaterial)
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(productQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(productQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
                }

                if let msg = statusMessage {
                    Section("Result") {
                        Text(msg)
                            .foregroundStyle(.primary)
                    }
                }

//                if let existing = foundExistingProduct,
//                   let aisleId = existing.aisleId,
//                   let aisle = aislesForStore.first(where: { $0.id == aisleId }) {
//
//                    Section("Product already known") {
//                        Text("\"\(existing.name)\" is already assigned to aisle \(aisle.nameOrNumber).")
//                            .font(.body)
//                    }
//                } else if let aisle = suggestedAisle {
//                    Section("Suggested aisle") {
//                        Text("It looks like the product belongs to aisle:")
//                            .font(.subheadline)
//                        Text("Aisle \(aisle.nameOrNumber)")
//                            .font(.headline)
//
//                        if !aisle.keywords.isEmpty {
//                            Text("On the sign: \(aisle.keywords.joined(separator: ", "))")
//                                .font(.footnote)
//                                .foregroundStyle(.secondary)
//                        }
//
//                        Button("Assign and save") {
//                            assignProduct(to: aisle)
//                        }
//                    }
//                }

                if isCallingGPT {
                    Section("AI") {
                        ProgressView("Asking AI…")
                    }
                }

                if let existing = foundExistingProduct,
                   let aisleId = existing.aisleId,
                   let aisle = aislesForStore.first(where: { $0.id == aisleId }) {

                    Section("Known product") {
                        Text("\"\(existing.name)\" is already assigned to aisle \(aisle.nameOrNumber).")
                    }

                } else if !gptCandidates.isEmpty {
                    Section("AI aisle suggestions") {
                        ForEach(gptCandidates.prefix(3), id: \.aisleId) { cand in
                            if let uuid = UUID(uuidString: cand.aisleId),
                               let aisle = aislesForStore.first(where: { $0.id == uuid }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Aisle \(aisle.nameOrNumber)")
                                        .font(.headline)
                                    Text("Confidence: \(cand.confidence_label) (\(Int(cand.confidence_score * 100))%)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(cand.reason)
                                        .font(.footnote)
                                }
                                Button("Assign product to this aisle") {
                                    assignProduct(to: aisle)
                                }
                            }
                        }
                    }

                    if suggestedAisle == nil {
                        Section("No confident match") {
                            Text("AI could not confidently pick a single aisle. You can assign manually or add a new aisle.")
                                .font(.footnote)
                        }
                    }
                } else if let aisle = suggestedAisle {
                    Section("Local suggestion") {
                        Text("Looks like the product belongs to aisle \(aisle.nameOrNumber).")
                        Button("Assign product to this aisle") {
                            assignProduct(to: aisle)
                        }
                    }
                }
//                Color.clear
//                    .contentShape(Rectangle())
//                    .onTapGesture {
//                        isProductQueryFocused = false
//                    }
//                    .allowsHitTesting(true)
            }
            .scrollDismissesKeyboard(.interactively)
            //            .simultaneousGesture(
            //                TapGesture().onEnded {
            //                    isProductQueryFocused = false
            //                }
            //            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isProductQueryFocused = false
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            //        .toolbar {
            //            ToolbarItemGroup(placement: .keyboard) {
            //                Spacer()
            //                Button("Done") {
            //                    isProductQueryFocused = false
            //                }
            //            }
            //        }
            //        .onTapGesture {
            //            isProductQueryFocused = false
            //        }
            //        .simultaneousGesture(
            //            TapGesture().onEnded {
            //                isProductQueryFocused = false
            //            }
            //        )
            .navigationTitle("Product Search")
            .onAppear {
                // ✅ רץ פעם אחת בלבד, ורק אם הגיע טקסט מהמסך הקודם
                guard !didAutoSearch else { return }
                let q = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return }

                didAutoSearch = true
                productQuery = q
                runSearch()
            }
        }
//        .simultaneousGesture(
//            TapGesture().onEnded {
//                isProductQueryFocused = false
//            }
//        )
    }

    // MARK: - לוגיקה

    private func runSearch() {
        let q = productQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !q.isEmpty else {
            statusMessage = "Type a product name to search."
            foundExistingProduct = nil
            suggestedAisle = nil
            return
        }

        statusMessage = nil
        foundExistingProduct = nil
        suggestedAisle = nil

        // 1. האם יש מוצר מוכר קודם?
        if let existing = productsForStore.first(where: { $0.name.lowercased().contains(q) }) {
            foundExistingProduct = existing
            if existing.aisleId == nil {
                statusMessage = "This product is known, but it is not assigned to any aisle yet."
            } else {
                statusMessage = "This product is already in the database."
            }
            return
        }

        // 2. לנסות למצוא שורה לפי keywords (לוקאלי)
        if let localBest = bestMatchingAisle(for: q) {
            suggestedAisle = localBest
            statusMessage = "No known product, but found a suitable aisle locally by keywords."
            return
        }

        // 3. If local didn't find anything – call GPT
        // ✅ Solution 2: if the store has no aisles yet, don't call AI, show a better message.
        if aislesForStore.isEmpty {
            statusMessage = "This store has no aisles yet. Add an aisle (upload a sign) and then try searching again."
            isCallingGPT = false
            gptCandidates = []
            suggestedAisle = nil
            return
        }

        // 3. אם גם לוקאלי לא מצא – לקרוא ל-GPT
        Task {
            await runGPTSuggestion(for: q)
        }
    }

    private func runGPTSuggestion(for query: String) async {
        if aislesForStore.isEmpty {
            await MainActor.run {
                self.isCallingGPT = false
                self.gptCandidates = []
                self.suggestedAisle = nil
                self.statusMessage = "This store has no aisles yet. Add an aisle (upload a sign) and then try searching again."
            }
            return
        }

        await MainActor.run {
            self.isCallingGPT = true
            self.statusMessage = "Asking AI for aisle suggestion…"
            self.gptCandidates = []
            self.suggestedAisle = nil
        }

        do {
            let resp = try await suggestAislesForProductUsingGPT(
                productName: query,
                aisles: aislesForStore,
                importance: .medium
            )

            await MainActor.run {
                self.isCallingGPT = false

                if resp.not_found || resp.candidates.isEmpty {
                    self.statusMessage = "AI could not find a suitable aisle. You may need to add a new aisle."
                    self.gptCandidates = []
                    self.suggestedAisle = nil
                    return
                }

                self.gptCandidates = resp.candidates

                // נבחר את המועמד הראשון כ"שורה מוצעת"
                if let top = resp.candidates.first,
                   let uuid = UUID(uuidString: top.aisleId),
                   let aisle = aislesForStore.first(where: { $0.id == uuid }) {
                    self.suggestedAisle = aisle
                    self.statusMessage =
                    """
                    AI suggestion: aisle \(aisle.nameOrNumber) (\(top.confidence_label), \(Int(top.confidence_score * 100))%).
                    """
                } else {
                    self.statusMessage = "AI returned candidates, but could not map them to existing aisles."
                }
            }
        } catch {
            await MainActor.run {
                self.isCallingGPT = false
                self.statusMessage = "Error calling AI: \(error.localizedDescription)"
            }
        }
    }

    /// מוצא שורה עם הכי הרבה התאמה למחרוזת (בשם השורה או במילות המפתח)
    private func bestMatchingAisle(for query: String) -> Aisle? {
        var bestScore = 0
        var bestAisle: Aisle?

        for aisle in aislesForStore {
            var score = 0

            // התאמה בשם השורה
            if aisle.nameOrNumber.lowercased().contains(query) {
                score += 2
            }

            // התאמה במילות מפתח
            for kw in aisle.keywords {
                if kw.lowercased().contains(query) {
                    score += 3
                }
            }

            if score > bestScore {
                bestScore = score
                bestAisle = aisle
            }
        }

        return bestScore > 0 ? bestAisle : nil
    }

    /// יצירת ProductItem חדש ושיוך לשורה
    private func assignProduct(to aisle: Aisle) {
        let name = productQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { return }

        let item = ProductItem(
            name: name,
            storeId: store.id,
            aisleId: aisle.id
        )
        context.insert(item)

        do {
            try context.save()
            foundExistingProduct = item
            suggestedAisle = nil
            statusMessage = "The product \"\(name)\" was saved and assigned to aisle \(aisle.nameOrNumber)."
        } catch {
            print("Failed to save product:", error)
            statusMessage = "Failed to save the product."
        }
    }
}
