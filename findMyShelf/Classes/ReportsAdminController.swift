import Foundation
import SwiftUI
import FirebaseFirestore

#if DEBUG
@MainActor
final class ReportsAdminController: ObservableObject {
    @Published var all: [ReportedUserReport] = []
    private var listener: ListenerRegistration?

    func start(firebase: FirebaseService) {
        stop()
        listener = firebase.startReportsListener { [weak self] items in
            self?.all = items
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    var newReports: [ReportedUserReport] { all.filter { !$0.isHandled } }
    var handledReports: [ReportedUserReport] { all.filter { $0.isHandled } }
}

struct ReportsAdminView: View {
    @ObservedObject private var firebase: FirebaseService
    @StateObject private var controller = ReportsAdminController()

    @State private var pendingAction: PendingAction? = nil
    @State private var showConfirm: Bool = false
    @State private var isWorking: Bool = false
    @State private var errorText: String? = nil

    init(firebase: FirebaseService) {
        self._firebase = ObservedObject(wrappedValue: firebase)
    }

    private enum ActionKind {
        case release
        case block
    }

    private struct PendingAction: Identifiable {
        let id = UUID()
        let kind: ActionKind
        let report: ReportedUserReport
    }

    var body: some View {
        List {
            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }

            Section(header: Text("New reports")) {
                if controller.newReports.isEmpty {
                    Text("No new reports.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.newReports) { r in
                        ReportRow(
                            report: r,
                            onRelease: { askConfirm(.release, r) },
                            onBlock: { askConfirm(.block, r) }
                        )
                    }
                }
            }

            Section(header: Text("Handled reports")) {
                if controller.handledReports.isEmpty {
                    Text("No handled reports.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.handledReports) { r in
                        ReportRow(
                            report: r,
                            onRelease: { askConfirm(.release, r) },
                            onBlock: nil // already handled; you can still allow block again if you want
                        )
                    }
                }
            }
        }
        .navigationTitle("Reports (Debug)")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking {
                ProgressView()
            }
        }
        .onAppear {
            controller.start(firebase: firebase)
        }
        .onDisappear {
            controller.stop()
        }
        .confirmationDialog(
            "Confirm",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(confirmButtonTitle(), role: pendingRole()) {
                runConfirmedAction()
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(confirmMessage())
        }
    }

    private func askConfirm(_ kind: ActionKind, _ report: ReportedUserReport) {
        pendingAction = PendingAction(kind: kind, report: report)
        showConfirm = true
    }

    private func confirmButtonTitle() -> String {
        switch pendingAction?.kind {
            case .release: return "Release (Delete report)"
            case .block: return "Block (Mark handled)"
            case .none: return "Confirm"
        }
    }

    private func pendingRole() -> ButtonRole? {
        // Deleting is destructive
        if pendingAction?.kind == .release { return .destructive }
        return nil
    }

    private func confirmMessage() -> String {
        guard let p = pendingAction else { return "" }
        switch p.kind {
            case .release:
                return "This will permanently delete this report. Continue?"
            case .block:
                return "This will mark the report as handled and move it to the handled section. Continue?"
        }
    }

    @MainActor
    private func runConfirmedAction() {
        guard let p = pendingAction else { return }
        isWorking = true
        errorText = nil

        Task { @MainActor in
            defer {
                isWorking = false
                pendingAction = nil
            }
            do {
                switch p.kind {
                    case .release:
                        try await firebase.deleteReport(reportId: p.report.id)
                    case .block:
                        try await firebase.markReportHandled(reportId: p.report.id)
                }
            } catch {
//                errorText = "Action failed."
                errorText = userFacingErrorMessage(error)
            }
        }
    }

    private func userFacingErrorMessage(_ error: Error) -> String {
        let ns = error as NSError

        // Auth errors (your own thrown errors)
        if ns.domain == "Auth", ns.code == 401 {
            return "You must be signed in to perform this action."
        }

        // Firestore / network
        if ns.domain == FirestoreErrorDomain {
            switch ns.code {
                case FirestoreErrorCode.permissionDenied.rawValue:
                    return "You don’t have permission to perform this action."
                case FirestoreErrorCode.unavailable.rawValue:
                    return "Network error. Please try again."
                case FirestoreErrorCode.notFound.rawValue:
                    return "This report no longer exists."
                default:
                    return "Database error (\(ns.code))."
            }
        }

        // Fallback
        return ns.localizedDescription.isEmpty
        ? "Unexpected error occurred."
        : ns.localizedDescription
    }
}

private struct ReportRow: View {
    let report: ReportedUserReport
    let onRelease: (() -> Void)?
    let onBlock: (() -> Void)?

    private func dateString(_ d: Date?) -> String {
        guard let d else { return "—" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.isHandled ? "Handled" : "New")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                Spacer()
                Text(dateString(report.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                Text("Reported user: \(report.reportedUserId)")
                Text("Reporter: \(report.reporterUserId)")
                Text("Reason: \(report.reason)")
                if !report.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Details: \(report.details)")
                } else {
                    Text("Details: (empty)")
                        .foregroundStyle(.secondary)
                }
                if let store = report.storeRemoteId {
                    Text("Store: \(store)")
                }
                if let context = report.context {
                    Text("Context: \(context)")
                        .foregroundStyle(.secondary)
                }
                if report.isHandled {
                    Text("Handled at: \(dateString(report.handledAt))")
                        .foregroundStyle(.secondary)
                    if let by = report.handledByUserId {
                        Text("Handled by: \(by)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.footnote)

            HStack(spacing: 10) {
                if let onRelease {
                    Button("Release") { onRelease() }
                        .buttonStyle(.bordered)
                }
                if let onBlock {
                    Button("Block") { onBlock() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
        }
        .padding(.vertical, 6)
    }
}
#endif
