//
//  findMyShelfApp.swift
//  findMyShelf
//
//  Created by shay moreno on 18/11/2025.
//

import SwiftUI
import FirebaseCore

@main
struct findMyShelfApp: App {

    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // כאן יוצרים container ל-SwiftData עם המודל Store
        .modelContainer(for: [Store.self, Aisle.self, ProductItem.self])
    }
}
