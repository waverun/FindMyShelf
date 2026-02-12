//import SwiftUI
//
//var bottomButtonsBar: some View {
//    ZStack(alignment: .topTrailing) {
//        HStack(spacing: 18) {
//
//            // If location is blocked, the only meaningful action here is opening Settings.
//            if let status = locationManager.authorizationStatus,
//               status == .denied || status == .restricted {
//
//                IconBarButton(
//                    systemImage: "gearshape",
//                    accessibilityLabel: "Open Settings",
//                    isEnabled: true
//                ) {
//                    if let url = URL(string: UIApplication.openSettingsURLString) {
//                        UIApplication.shared.open(url)
//                    }
//                }
//
//                Spacer()
//
//            } else {
//
//                // Back to previous selected store
//                if selectedStoreId == nil, let prev = previousSelectedStoreId, !prev.isEmpty {
//                    IconBarButton(
//                        systemImage: "arrow.uturn.backward",
//                        accessibilityLabel: "Back to selected store",
//                        isEnabled: true
//                    ) {
//                        selectedStoreId = prev
//                    }
//                }
//
//                // Allow location (only when not determined)
//                if locationManager.authorizationStatus == .notDetermined {
//                    IconBarButton(
//                        systemImage: "location",
//                        accessibilityLabel: "Allow location",
//                        isEnabled: true
//                    ) {
//                        locationManager.requestPermission()
//                    }
//                }
//
//                // Refresh location
//                IconBarButton(
//                    systemImage: "arrow.clockwise",
//                    accessibilityLabel: "Refresh location",
//                    isEnabled: isAuthorized
//                ) {
//                    locationManager.startUpdating()
//                }
//
//                // Find nearby
//                IconBarButton(
//                    systemImage: "magnifyingglass",
//                    accessibilityLabel: "Find nearby stores",
//                    isEnabled: hasLocation,
//                    isPrimary: true
//                ) {
//                    guard let loc = locationManager.currentLocation else { return }
//                    finder.searchNearby(from: loc)
//                }
//
//                IconBarButton(
//                    systemImage: "exclamationmark.bubble",
//                    accessibilityLabel: "Report a user",
//                    isEnabled: true
//                ) {
//                    showReportSheet = true
//                }
//
//#if DEBUG
//                IconBarButton(
//                    systemImage: "ladybug",
//                    accessibilityLabel: "Reports admin (Debug)",
//                    isEnabled: true
//                ) {
//                    goToReportsAdmin = true
//                }
//#endif
//                IconBarButton(
//                    systemImage: "questionmark.circle",
//                    accessibilityLabel: "Help",
//                    isEnabled: true
//                ) {
//                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
//                        showLongPressHint.toggle()
//                    }
//                }
//
//                Spacer(minLength: 0)
//            }
//        }
//        .padding(.horizontal, 16)
//        .padding(.top, 10)
//        .padding(.bottom, 10)
//        .background(.ultraThinMaterial)
//        .ignoresSafeArea(.keyboard, edges: .bottom)
//
//        if showLongPressHint {
//            LongPressHintBubble {
//                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
//                    showLongPressHint = false
//                }
//            }
//            .padding(.trailing, 12)
//            .offset(y: -70)   // מרים מעל ה-bar
//            .transition(.move(edge: .bottom).combined(with: .opacity))
//        }
//    }
//    }
