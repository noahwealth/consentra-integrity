import SwiftUI

/// Figma 26 · Activity: every share, view and revoke, newest first.
@MainActor
struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            let events = ActivityEvent.from(shares: model.shares)
            List {
                if let error = model.error {
                    ErrorBanner(message: error) { await model.refresh() }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if events.isEmpty {
                    ContentUnavailableView("No activity yet", systemImage: "clock",
                                           description: Text("Shares, views by clinicians, and revokes will appear here."))
                        .listRowBackground(Color.clear)
                }
                ForEach(events) { e in
                    NavigationLink { AccessDetailView(token: e.shareToken) } label: { ActivityRow(event: e) }
                }
            }
            .navigationTitle("Activity")
            .refreshable { await model.refresh() }
            .task {
                while !Task.isCancelled {
                    await model.refresh()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }
}

struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).lineLimit(3)
                Text("\(event.date.relative) · \(event.categories.map(\.title).joined(separator: ", "))")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch event.kind {
        case .created: "Shared with \(event.shareLabel)"
        case .viewed: "\(event.shareLabel) opened your record on \(event.device ?? "a browser")"
        case .revoked: "You revoked access for \(event.shareLabel)"
        }
    }
    private var symbol: String {
        switch event.kind { case .created: "square.and.arrow.up"; case .viewed: "eye.fill"; case .revoked: "xmark.shield.fill" }
    }
    private var tint: Color {
        switch event.kind { case .created: .blue; case .viewed: .green; case .revoked: .red }
    }
}
