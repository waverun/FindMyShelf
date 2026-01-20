import SwiftUI
import SwiftData

struct ManualStoreSheet: View {
    let existingStores: [Store]
    let onPickExisting: (Store) -> Void
    let onSaveNew: (_ name: String, _ address: String?, _ city: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""

    @State private var name: String = ""
    @State private var addressLine: String = ""
    @State private var city: String = ""

    private var filteredExisting: [Store] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return existingStores }

        return existingStores.filter { s in
            let n = s.name.lowercased()
            let a = (s.addressLine ?? "").lowercased()
            let c = (s.city ?? "").lowercased()
            return n.contains(q) || a.contains(q) || c.contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Find a saved store") {
                    TextField("Search by name / address / city…", text: $searchText)
                        .textInputAutocapitalization(.never)

                    if filteredExisting.isEmpty {
                        Text("No saved stores match.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredExisting) { store in
                            Button {
                                onPickExisting(store)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(store.name)
                                        .foregroundStyle(.primary)

                                    let line = [
                                        store.addressLine,
                                        store.city
                                    ]
                                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " • ")

                                    if !line.isEmpty {
                                        Text(line)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Add a new store manually") {
                    TextField("Store name", text: $name)

                    TextField("Address (optional)", text: $addressLine)

                    TextField("City (optional)", text: $city)

                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }

                        let addr = addressLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        let c = city.trimmingCharacters(in: .whitespacesAndNewlines)

                        onSaveNew(
                            trimmedName,
                            addr.isEmpty ? nil : addr,
                            c.isEmpty ? nil : c
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Choose store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
