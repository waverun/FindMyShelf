import SwiftUI
import SwiftData

struct ManualStoreSheet: View {
    let existingStores: [Store]
    let onPickExisting: (Store) -> Void
    let onSaveNew: (_ name: String, _ address: String?, _ city: String?) -> Void
    let onDelete: (Store) -> Void   // ✅ חדש

    @Environment(\.dismiss) private var dismiss

    @State private var storePendingDelete: Store?
    @State private var confirmText: String = ""
    @State private var showDeleteConfirm: Bool = false

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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    // Search
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Find a saved store")
                            .font(.headline)

                        TextField("Search by name / address / city…", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // Cards
                    if filteredExisting.isEmpty {
                        EmptyStateCard(
                            title: "No matches",
                            subtitle: "Try another search or add a store manually.",
                            icon: "magnifyingglass"
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(Array(filteredExisting.prefix(30).enumerated()), id: \.element.id) { index, store in
                                    ManualStoreCard(
                                        title: store.name,
                                        subtitle: [
                                            store.addressLine,
                                            store.city
                                        ]
                                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                            .filter { !$0.isEmpty }
                                            .joined(separator: " • "),
                                        colorIndex: index,
                                        onPick: {
                                            onPickExisting(store)
                                            dismiss()
                                        },
                                        onRequestDelete: {
                                            storePendingDelete = store
                                            confirmText = ""
                                            showDeleteConfirm = true
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }

                    // Add manually
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add a store manually")
                            .font(.headline)

                        VStack(spacing: 10) {
                            TextField("Store name (required)", text: $name)
                                .textFieldStyle(.roundedBorder)

                            TextField("Address (optional)", text: $addressLine)
                                .textFieldStyle(.roundedBorder)

                            TextField("City (optional)", text: $city)
                                .textFieldStyle(.roundedBorder)

                            Button {
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
                            } label: {
                                Text("Save store")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.thinMaterial)
                            .shadow(radius: 10, y: 5)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
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
        // ✅ Sheet אישור מחיקה "קשה"
        .sheet(isPresented: $showDeleteConfirm) {
            DeleteStoreConfirmSheet(
                storeName: storePendingDelete?.name ?? "",
                confirmText: $confirmText,
                onCancel: {
                    storePendingDelete = nil
                    showDeleteConfirm = false
                },
                onDelete: {
                    guard let s = storePendingDelete else { return }
                    onDelete(s)
                    storePendingDelete = nil
                    showDeleteConfirm = false
                }
            )
        }
    }
}

// MARK: - Card

private struct ManualStoreCard: View {
    let title: String
    let subtitle: String
    let colorIndex: Int
    let onPick: () -> Void
    let onRequestDelete: () -> Void   // ✅ חדש

    var body: some View {
        let base = color(for: colorIndex)

        ZStack(alignment: .topTrailing) {
            Button(action: onPick) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(
                            colors: [base.opacity(0.95), base.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(radius: 12, y: 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(2)
                        } else {
                            Text("No address saved")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                        }

                        Text("Tap to choose")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.22))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(16)
                }
                .frame(width: 280, height: 150)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    private func color(for index: Int) -> Color {
        let palette: [Color] = [.blue, .purple, .indigo, .teal, .mint, .pink, .orange]
        return palette[index % palette.count]
    }
}
