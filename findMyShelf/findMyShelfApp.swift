import SwiftUI
import FirebaseCore

@main
struct findMyShelfApp: App {

    init() {
        FirebaseApp.configure()
    }

    @StateObject private var firebase = FirebaseService()   // ✅ add
    @StateObject private var uploadFlow = UploadFlowCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(firebase)               // ✅ add
                .environmentObject(uploadFlow)
        }
        .modelContainer(for: [Store.self, Aisle.self, ProductItem.self])
    }
}
