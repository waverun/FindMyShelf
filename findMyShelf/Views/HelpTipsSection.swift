import SwiftUI

// MARK: - Model

struct HelpTip: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
    let accent: String
}

// MARK: - Section View

struct HelpTipsSection: View {
    @Binding var filterText: String
    @Binding var isExpanded: Bool
    
    private let tips: [HelpTip] = [
        HelpTip(
            icon: "location",
            title: "Location permission",
            body: "• Allow location for nearby stores\n• If you choose ‘Only Once’, you can refresh later\n• Without permission, use ‘Add manually’",
            accent: "Location"
        ),
        HelpTip(
            icon: "hand.tap",
            title: "Use without location",
            body: "• Pick a store manually\n• Or reuse a previously selected store\n• Search and browse still works",
            accent: "Manual"
        ),
        HelpTip(
            icon: "cart",
            title: "What this app does",
            body: "Search a product name and get the aisle(s) where it should be, even if the exact word is not written.",
            accent: "Search"
        ),
        HelpTip(
            icon: "camera.viewfinder",
            title: "Add or improve aisles",
            body: "• Scan an aisle sign photo\n• Or add an aisle manually\n• Add keywords for better search",
            accent: "Aisles"
        ),
        HelpTip(
            icon: "person.badge.key",
            title: "Sign‑in required for edits",
            body: "Browsing is open. To add, edit or upload photos, sign in with Apple or Google.",
            accent: "Account"
        ),
        HelpTip(
            icon: "shared.with.you",
            title: "Shared community data",
            body: "All stores and aisles are shared. Your improvements help everyone.",
            accent: "Shared"
        ),
        HelpTip(
            icon: "exclamationmark.bubble",
            title: "Reporting & moderation",
            body: "You can report misuse. Changes and deletions are monitored.",
            accent: "Safety"
        )
    ]
    
    private var filteredTips: [HelpTip] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return tips }
        return tips.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.body.localizedCaseInsensitiveContains(q)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            
            TextField("Search tips…", text: $filterText)
                .textFieldStyle(.roundedBorder)
            
            if isExpanded {
                content
            }
        }
        .padding(.top, 6)
    }
    
    // MARK: - Subviews
    
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Getting started")
                .font(.headline)
            
            Button(isExpanded ? "Hide" : "Show") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
            
            Spacer()
        }
    }
    
    private var content: some View {
        Group {
            if filteredTips.isEmpty {
                EmptyStateCard(
                    title: "No matching tips",
                    subtitle: "Try another keyword",
                    icon: "magnifyingglass"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(filteredTips) { tip in
                            HelpTipCard(tip: tip)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - Card

struct HelpTipCard: View {
    let tip: HelpTip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: tip.icon)
                    .font(.title3)
                
                Text(tip.title)
                    .font(.headline)
                
                Spacer()
            }
            
            ScrollView(.vertical, showsIndicators: true) {
                Text(tip.body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 2) // keeps text away from the indicator
            }
            .frame(maxHeight: 86)
            
            Spacer(minLength: 6)
            
            HStack {
                Text(tip.accent)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 320, height: 190)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
