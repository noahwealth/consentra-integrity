import SwiftUI

/// What Access Detail should show. Never a spinner once a refresh has finished or failed (review fix).
enum AccessDetailState: Equatable {
    case loading, failed(String), notFound, loaded(Share)

    static func resolve(share: Share?, error: String?, hasLoaded: Bool) -> AccessDetailState {
        if let share { return .loaded(share) }
        if let error { return .failed(error) }
        return hasLoaded ? .notFound : .loading
    }
}

/// Figma 16 · Access Detail and 17 · Revoke Access.
@MainActor
struct AccessDetailView: View {
    @Environment(AppModel.self) private var model
    let token: String
    @State private var confirmRevoke = false
    @State private var revoking = false
    @State private var error: String?

    var body: some View {
        Group {
            switch AccessDetailState.resolve(share: model.share(token: token), error: model.error, hasLoaded: model.lastRefresh != nil) {
            case .loaded(let share):
                content(share)
            case .failed(let message):
                ScrollView { ErrorBanner(message: message) { await model.refresh() }.padding(16) }
            case .notFound:
                ContentUnavailableView("Share not found", systemImage: "questionmark.folder",
                                       description: Text("This share no longer exists on the server."))
            case .loading:
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Keep the view log live while this screen is open, so a clinician opening the link shows up here.
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func content(_ share: Share) -> some View {
        List {
            // Stale-data warning: polling failed, so status and views may be out of date.
            if let error = model.error {
                ErrorBanner(message: error) { await model.refresh() }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                VStack(spacing: 8) {
                    Image(systemName: share.status == .active ? "stethoscope" : "lock.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background((share.status == .active ? Theme.indigo : Color.gray).gradient, in: Circle())
                    Text(share.displayLabel).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    Text("Shared \(share.createdAt.formatted(date: .long, time: .shortened))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    StatusChip(status: share.status)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Can access") {
                ForEach(Category.allCases) { c in
                    let shared = share.categories.contains(c)
                    HStack(spacing: 12) {
                        CategoryIcon(category: c).opacity(shared ? 1 : 0.35)
                        Text(c.title).foregroundStyle(shared ? .primary : .tertiary)
                        Spacer()
                        if shared {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        } else {
                            Text("Not shared").font(.footnote).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section("Details") {
                LabeledContent("Created", value: share.createdAt.formatted(date: .abbreviated, time: .shortened))
                switch share.status {
                case .active:
                    LabeledContent("Expires", value: "in \(countdown(to: share.expiresAt))")
                case .expired:
                    LabeledContent("Expired", value: share.expiresAt.formatted(date: .abbreviated, time: .shortened))
                case .revoked:
                    LabeledContent("Revoked", value: share.revokedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                }
                if share.status == .active {
                    NavigationLink("Show QR code") { PresentView(share: share, walletAvailable: model.record?.walletAvailable ?? false) }
                }
            }

            Section {
                if share.views.isEmpty {
                    Text("Not opened yet").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(share.views.enumerated().reversed()), id: \.offset) { _, v in
                        HStack {
                            Image(systemName: "eye.fill").foregroundStyle(.green)
                            Text("Opened on \(v.deviceLabel)")
                            Spacer()
                            Text(v.at.relative).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Views · \(share.views.count)")
            } footer: {
                Text("Every time the link is opened, it's logged here.")
            }

            if share.status == .active {
                Section {
                    Button(role: .destructive) { confirmRevoke = true } label: {
                        HStack { Spacer(); if revoking { ProgressView() } else { Text("Revoke Access").bold() }; Spacer() }
                    }
                    .disabled(revoking)
                    .accessibilityIdentifier("access.revoke")
                } footer: {
                    Text("The link stops working immediately, including from the QR code and Wallet pass.")
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .confirmationDialog("Revoke access for \(share.displayLabel)?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Revoke Access", role: .destructive) { Task { await revoke(share) } }
        } message: {
            Text("They'll see \u{201C}Access ended\u{201D} the next time the page checks, within a few seconds.")
        }
    }

    private func revoke(_ share: Share) async {
        revoking = true; error = nil
        defer { revoking = false }
        do { try await model.revoke(share) } catch { self.error = error.localizedDescription }
    }
}
