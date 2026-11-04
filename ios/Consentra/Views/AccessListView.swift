import SwiftUI

/// Figma 15 · Access Management.
@MainActor
struct AccessListView: View {
    @Environment(AppModel.self) private var model

    private var active: [Share] { model.shares.filter { $0.status == .active } }
    private var ended: [Share] { model.shares.filter { $0.status != .active } }

    var body: some View {
        List {
            if let error = model.error {
                ErrorBanner(message: error) { await model.refresh() }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if model.shares.isEmpty {
                ContentUnavailableView("No one has access", systemImage: "lock.shield",
                                       description: Text("When you share with a provider, it shows up here. You can revoke it at any time."))
                    .listRowBackground(Color.clear)
            }
            if !active.isEmpty {
                Section("Active · \(active.count)") {
                    ForEach(active) { s in
                        NavigationLink { AccessDetailView(token: s.token) } label: { ShareRow(share: s) }
                            .accessibilityIdentifier("access.row.active")
                    }
                }
            }
            if !ended.isEmpty {
                Section("Ended") {
                    ForEach(ended) { s in NavigationLink { AccessDetailView(token: s.token) } label: { ShareRow(share: s) } }
                }
            }
        }
        .navigationTitle("Manage Access")
        .refreshable { await model.refresh() }
        .task { await model.refresh() }
    }
}

struct ShareRow: View {
    let share: Share

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: share.status == .active ? "stethoscope" : "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background((share.status == .active ? Theme.indigo : Color.gray).gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(share.displayLabel).font(.body.weight(.medium)).lineLimit(1)
                Text(share.categories.map(\.title).joined(separator: ", "))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    StatusChip(status: share.status)
                    if share.status == .active {
                        Text("Expires in \(countdown(to: share.expiresAt))").font(.caption).foregroundStyle(.secondary)
                    }
                    if !share.views.isEmpty {
                        Text("· \(share.views.count) view\(share.views.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct StatusChip: View {
    let status: ShareStatus
    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
    private var color: Color {
        switch status { case .active: .green; case .expired: .gray; case .revoked: .red }
    }
}
