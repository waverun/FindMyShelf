// MARK: - UI building blocks

import SwiftUI
import FirebaseAuth

struct EditStoreSheet: View {
    let store: Store
    let onSave: (_ name: String, _ address: String?, _ city: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showLoginRequiredAlert = false
    @State private var loginAppleCoordinator = AppleSignInCoordinator()

    @State private var name: String
    @State private var addressLine: String
    @State private var city: String

    init(store: Store,
         onSave: @escaping (_ name: String, _ address: String?, _ city: String?) -> Void) {
        self.store = store
        self.onSave = onSave
        _name = State(initialValue: store.name)
        _addressLine = State(initialValue: store.addressLine ?? "")
        _city = State(initialValue: store.city ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Store") {
                    TextField("Store name", text: $name)
                    TextField("Address", text: $addressLine)
                    TextField("City", text: $city)
                }

                Section {
//                    Button("Save") {
//                        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
//                        guard !n.isEmpty else { return }
//
//                        let a = addressLine.trimmingCharacters(in: .whitespacesAndNewlines)
//                        let c = city.trimmingCharacters(in: .whitespacesAndNewlines)
//
//                        onSave(n,
//                               a.isEmpty ? nil : a,
//                               c.isEmpty ? nil : c)
//
//                        dismiss()
//                    }
                    Button("Save") {
                        if Auth.auth().currentUser == nil {
                            showLoginRequiredAlert = true
                            return
                        }

                        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !n.isEmpty else { return }

                        let a = addressLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        let c = city.trimmingCharacters(in: .whitespacesAndNewlines)

                        onSave(n,
                               a.isEmpty ? nil : a,
                               c.isEmpty ? nil : c)

                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Edit store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Login required", isPresented: $showLoginRequiredAlert) {
                Button("Cancel", role: .cancel) {}

                Button("Continue with Google") {
                    Task { @MainActor in
                        try? await signInWithGoogle()
                    }
                }

                Button("Continue with Apple") {
                    Task { @MainActor in
                        loginAppleCoordinator.start()
                    }
                }
            } message: {
                Text("Please sign in to save changes.")
            }
        }
    }
}
