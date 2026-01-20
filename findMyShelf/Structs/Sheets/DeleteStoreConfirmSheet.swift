import SwiftUI

struct DeleteStoreConfirmSheet: View {
    let storeName: String
    @Binding var confirmText: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    private var firstWordUpper: String {
        let trimmed = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? "STORE"
        return first.uppercased()
    }

    private var expected: String { "DELETE \(firstWordUpper)" }

    private var isValid: Bool {
        confirmText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == expected
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Delete store")
                    .font(.title3.bold())

                Text("This will permanently delete the store and all its aisles and products.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("To confirm, type: **\(expected)**")
                    .font(.footnote)

                TextField(expected, text: $confirmText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Text("Delete")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(16)
            .navigationTitle(storeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }
}
