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

    @FocusState private var isKeyboardFocused: Bool

    init(
        store: Store,
        onSave: @escaping (_ name: String, _ address: String?, _ city: String?) -> Void
    ) {
        self.store = store
        self.onSave = onSave
        _name = State(initialValue: store.name)
        _addressLine = State(initialValue: store.addressLine ?? "")
        _city = State(initialValue: store.city ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    Text("Edit store")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {

                        TextField("Store name (required)", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($isKeyboardFocused)

                        TextField("Address (optional)", text: $addressLine)
                            .textFieldStyle(.roundedBorder)
                            .focused($isKeyboardFocused)

                        TextField("City (optional)", text: $city)
                            .textFieldStyle(.roundedBorder)
                            .focused($isKeyboardFocused)

                        HStack(spacing: 12) {

                            // 💾 Save
                            Button {
                                isKeyboardFocused = false

                                if Auth.auth().currentUser == nil {
                                    showLoginRequiredAlert = true
                                    return
                                }

                                let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !n.isEmpty else { return }

                                let a = addressLine.trimmingCharacters(in: .whitespacesAndNewlines)
                                let c = city.trimmingCharacters(in: .whitespacesAndNewlines)

                                onSave(
                                    n,
                                    a.isEmpty ? nil : a,
                                    c.isEmpty ? nil : c
                                )

                                dismiss()
                            } label: {
                                Text("Save changes")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            // ❌ Cancel
                            Button {
                                isKeyboardFocused = false
                                dismiss()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
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
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { isKeyboardFocused = false }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isKeyboardFocused = false }
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
//// MARK: - UI building blocks
//
//import SwiftUI
//import FirebaseAuth
//
//struct EditStoreSheet: View {
//    let store: Store
//    let onSave: (_ name: String, _ address: String?, _ city: String?) -> Void
//
//    @Environment(\.dismiss) private var dismiss
//
//    @State private var showLoginRequiredAlert = false
//    @State private var loginAppleCoordinator = AppleSignInCoordinator()
//
//    @State private var name: String
//    @State private var addressLine: String
//    @State private var city: String
//
//    init(store: Store,
//         onSave: @escaping (_ name: String, _ address: String?, _ city: String?) -> Void) {
//        self.store = store
//        self.onSave = onSave
//        _name = State(initialValue: store.name)
//        _addressLine = State(initialValue: store.addressLine ?? "")
//        _city = State(initialValue: store.city ?? "")
//    }
//
//    var body: some View {
//        NavigationStack {
//            Form {
//                Section("Store") {
//                    TextField("Store name", text: $name)
//                    TextField("Address", text: $addressLine)
//                    TextField("City", text: $city)
//                }
//
//                Section {
//                    Button("Save") {
//                        if Auth.auth().currentUser == nil {
//                            showLoginRequiredAlert = true
//                            return
//                        }
//
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
//                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
//                }
//            }
//            .navigationTitle("Edit store")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("Cancel") { dismiss() }
//                }
//            }
//            .alert("Login required", isPresented: $showLoginRequiredAlert) {
//                Button("Cancel", role: .cancel) {}
//
//                Button("Continue with Google") {
//                    Task { @MainActor in
//                        try? await signInWithGoogle()
//                    }
//                }
//
//                Button("Continue with Apple") {
//                    Task { @MainActor in
//                        loginAppleCoordinator.start()
//                    }
//                }
//            } message: {
//                Text("Please sign in to save changes.")
//            }
//        }
//    }
//}
