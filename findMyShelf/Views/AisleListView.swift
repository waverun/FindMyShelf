import SwiftUI
import SwiftData
//import PhotosUI

struct AisleListView: View {
    @Environment(\.modelContext) private var context

    let store: Store

    // כל השורות בבסיס הנתונים
    @Query(sort: \Aisle.createdAt, order: .forward)
    private var allAisles: [Aisle]

    @State private var selectedAisleID: UUID?
    @State private var isEditingSelected: Bool = false

    @State private var newAisleName: String = ""

    // חיפוש / פילטר
    @State private var filterText: String = ""

    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case newAisleName
        case filter
    }

    private var selectedAisle: Aisle? {
        guard let id = selectedAisleID else { return nil }
        return aislesForStore.first(where: { $0.id == id })
    }

    // שורות רק של החנות הזו
    private var aislesForStore: [Aisle] {
        allAisles
            .filter { $0.storeId == store.id }
            .sorted {
                $0.nameOrNumber.localizedStandardCompare($1.nameOrNumber) == .orderedAscending
            }
    }

    //    private var aislesForStore: [Aisle] {
    //        allAisles.filter { $0.storeId == store.id }
    //    }

    // שורות אחרי פילטר
    private var filteredAisles: [Aisle] {
        let text = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else {
            return aislesForStore
        }
        return aislesForStore.filter { aisle in
            let nameHit = aisle.nameOrNumber.lowercased().contains(text)
            let keywordHit = aisle.keywords.contains { kw in
                kw.lowercased().contains(text)
            }
            return nameHit || keywordHit
        }
    }

    var body: some View {
        ScrollView {
            VStack {
                // שורת חיפוש
                HStack {
                    //                TextField("Search for an aisle or keywords…", text: $filterText)
                    //                    .textFieldStyle(.roundedBorder)
                    TextField("Search for an aisle or keywords…", text: $filterText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .filter)
                        .submitLabel(.search)
                }
                .padding([.horizontal, .top])

                // כרטיסיות שורות – אופקי
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        if filteredAisles.isEmpty {
                            Text("No aisles were found matching your search.")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                        } else {
                            ForEach(Array(filteredAisles.enumerated()), id: \.element.id) { index, aisle in
                                AisleCard(
                                    title: aisle.nameOrNumber,
                                    keywords: aisle.keywords,
                                    colorIndex: index,
                                    isSelected: aisle.id == selectedAisleID
                                ) {
                                    // בחירה בלבד (לא עריכה)
                                    selectedAisleID = aisle.id
                                    isEditingSelected = false
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { _ in
                            focusedField = nil
                            guard selectedAisleID != nil else { return }
                            withAnimation(.easeInOut(duration: 0.36)) {
                                selectedAisleID = nil
                                isEditingSelected = false
                            }
                        }
                )

                // פאנל למטה
                Group {
                    if let aisle = selectedAisle {
                        AisleBottomPanel(
                            aisle: aisle,
                            isEditing: $isEditingSelected,
                            onDelete: {
                                context.delete(aisle)
                                try? context.save()
                                selectedAisleID = nil
                                isEditingSelected = false
                            },
                            onSave: { newName, newKeywords in
                                aisle.nameOrNumber = newName
                                aisle.keywords = newKeywords
                                try? context.save()
                                isEditingSelected = false
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.36), value: selectedAisleID)

                // הוספה ידנית
                HStack {
                    //                TextField("...number / new asile name", text: $newAisleName)
                    //                    .textFieldStyle(.roundedBorder)

                    TextField("...number / new aisle name", text: $newAisleName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .newAisleName)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil   // סוגר מקלדת
                                                 // אופציונלי: להוסיף שורה אוטומטית
                                                 // addAisle()
                        }

                    Button("הוסף") {
                        addAisle()
                    }
                    .disabled(newAisleName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .contentShape(Rectangle())     // חשוב!
            .onTapGesture {
                focusedField = nil
            }
        }
        .navigationTitle("Aisles map \(store.name)")
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - פעולות בסיסיות

    private func addAisle() {
        let trimmed = newAisleName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let aisle = Aisle(nameOrNumber: trimmed, storeId: store.id)
        context.insert(aisle)
        do {
            try context.save()
            newAisleName = ""
        } catch {
            print("Failed to save aisle:", error)
        }
    }
}

private struct AisleCard: View {
    let title: String
    let keywords: [String]
    let colorIndex: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        let base = color(for: colorIndex)

        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        colors: [base.opacity(0.95), base.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(isSelected ? .white.opacity(0.9) : .white.opacity(0.18),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(radius: isSelected ? 16 : 12, y: isSelected ? 8 : 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Aisle \(title)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if !keywords.isEmpty {
                        Text(keywords.prefix(6).joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                    } else {
                        Text("No keywords")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Text(isSelected ? "Selected" : "Tap to select")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
                .padding(16)
            }
            .frame(width: 280, height: 160)
        }
        .buttonStyle(.plain)
    }

    private func color(for index: Int) -> Color {
        let palette: [Color] = [.blue, .purple, .indigo, .teal, .mint, .pink, .orange]
        return palette[index % palette.count]
    }
}

private struct AisleBottomPanel: View {
    @Bindable var aisle: Aisle
    @Binding var isEditing: Bool

    let onDelete: () -> Void
    let onSave: (_ newName: String, _ newKeywords: [String]) -> Void

    @State private var showDeleteConfirm = false

    @State private var draftName: String = ""
    @State private var draftKeywordsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("Selected aisle")
                    .font(.headline)
                Spacer()

                if isEditing {
                    Button("Done") {
                        let kws = draftKeywordsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        onSave(draftName.trimmingCharacters(in: .whitespacesAndNewlines), kws)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Edit") {
                        draftName = aisle.nameOrNumber
                        draftKeywordsText = aisle.keywords.joined(separator: ", ")
                        isEditing = true
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !isEditing {
                Text("Aisle \(aisle.nameOrNumber)")
                    .font(.title3.bold())

                if !aisle.keywords.isEmpty {
                    Text("Keywords: \(aisle.keywords.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No keywords yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete aisle", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .confirmationDialog(
                    "Delete this aisle?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This action cannot be undone.")
                }
            } else {
                TextField("Aisle name/number", text: $draftName)
                    .textFieldStyle(.roundedBorder)

                TextField("Keywords (comma separated)", text: $draftKeywordsText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                HStack {
                    Button(role: .destructive) {
                        isEditing = false
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        let kws = draftKeywordsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        onSave(draftName.trimmingCharacters(in: .whitespacesAndNewlines), kws)
                    } label: {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
