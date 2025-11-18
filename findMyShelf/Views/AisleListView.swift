import SwiftUI
import SwiftData

struct AisleListView: View {
    @Environment(\.modelContext) private var context

    let store: Store

    // כל השורות בבסיס הנתונים
    @Query(sort: \Aisle.createdAt, order: .forward)
    private var allAisles: [Aisle]

    @State private var newAisleName: String = ""

    // שורות רק של החנות הזו
    private var aislesForStore: [Aisle] {
        allAisles.filter { $0.storeId == store.id }
    }

    var body: some View {
        VStack {
            List {
                ForEach(aislesForStore) { aisle in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("שורה \(aisle.nameOrNumber)")
                            .font(.headline)
                        if !aisle.keywords.isEmpty {
                            Text(aisle.keywords.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteAisles)
            }

            HStack {
                TextField("מספר/שם שורה חדש…", text: $newAisleName)
                    .textFieldStyle(.roundedBorder)

                Button("הוסף") {
                    addAisle()
                }
                .disabled(newAisleName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .navigationTitle("מיפוי שורות – \(store.name)")
    }

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

    private func deleteAisles(at offsets: IndexSet) {
        for index in offsets {
            let aisle = aislesForStore[index]
            context.delete(aisle)
        }
        do {
            try context.save()
        } catch {
            print("Failed to delete aisles:", error)
        }
    }
}
