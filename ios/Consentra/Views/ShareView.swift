import SwiftUI

/// Figma 18 · Share hub.
@MainActor
struct ShareHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showConnect = false

    var body: some View {
        NavigationStack {
            List {
                if let error = model.error {
                    ErrorBanner(message: error) { await model.refresh() }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section {
                    if model.isConnected {
                        NavigationLink { ShareBuilderView() } label: {
                            ShareOptionRow(symbol: "qrcode", tint: .blue, title: "With a Provider",
                                           subtitle: "Pick what to share and for how long, then show a QR code")
                        }
                        .accessibilityIdentifier("share.provider")
                    } else {
                        Button { showConnect = true } label: {
                            ShareOptionRow(symbol: "link.badge.plus", tint: Theme.indigo, title: "Connect records first",
                                           subtitle: "Bring your history from home to share it")
                        }
                        .buttonStyle(.plain)
                    }
                    ShareOptionRow(symbol: "staroflife.fill", tint: .red, title: "Emergency Access",
                                   subtitle: "Coming soon").opacity(0.45)
                }
                Section("More") {
                    NavigationLink { AccessListView() } label: {
                        HStack {
                            ActionIcon(symbol: "key.fill", tint: .orange)
                            Text("Who Has Access")
                            Spacer()
                            Text("\(model.activeShares.count) active").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {} footer: {
                    Text("You choose what is shared, with whom, and for how long. Every view appears in Activity.")
                }
            }
            .navigationTitle("Share")
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showConnect) { ConnectFlow() }
        }
    }
}

struct ActionIcon: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct ShareOptionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Choose categories, duration and recipient, then create the share (Figma 05/06 layout, patient-initiated).
@MainActor
struct ShareBuilderView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Set<Category> = []
    @State private var duration: ShareDuration = .oneDay
    @State private var label = ""
    @State private var creating = false
    @State private var error: String?
    @State private var created: CreateShareResponse?

    var body: some View {
        List {
            Section {
                TextField("e.g. Dr. Rivera, Mass General", text: $label)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Who is this for?")
            } footer: {
                Text("Optional. Shown on the clinician's page and in your access list.")
            }

            Section {
                ForEach(Category.allCases) { c in
                    Button { toggle(c) } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: c)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.title).foregroundStyle(.primary)
                                Text("\(model.record?.items(c).count ?? 0) items · \(c.subtitle)")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selected.contains(c) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected.contains(c) ? Color.accentColor : Color(.tertiaryLabel))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected.contains(c) ? .isSelected : [])
                    .accessibilityIdentifier("category.\(c.rawValue)")
                }
            } header: {
                HStack {
                    Text("What to share")
                    Spacer()
                    Text("\(selected.count) of \(Category.allCases.count) selected")
                }
            } footer: {
                Text("Nothing is shared until you pick it. The clinician sees only these categories.")
            }

            Section("For how long") {
                Picker("Duration", selection: $duration) {
                    ForEach(ShareDuration.allCases) { Text($0.short).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if let error {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    Task { await create() }
                } label: {
                    Group { if creating { ProgressView().tint(.white) } else { Text("Create Share").bold() } }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(selected.isEmpty || creating)
                Text(selected.isEmpty ? "Select at least one category" : "Expires after \(duration.label) · Revoke anytime")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.bar)
        }
        .navigationTitle("Share with a Provider")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $created) { res in
            PresentView(share: res.share, walletAvailable: res.walletAvailable)
        }
    }

    private func toggle(_ c: Category) {
        if selected.contains(c) { selected.remove(c) } else { selected.insert(c) }
    }

    private func create() async {
        creating = true; error = nil
        defer { creating = false }
        do {
            let ordered = Category.allCases.filter(selected.contains)
            created = try await model.createShare(categories: ordered, duration: duration, label: label.trimmingCharacters(in: .whitespaces))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension CreateShareResponse: Hashable, Identifiable {
    var id: String { share.token }
    static func == (a: Self, b: Self) -> Bool { a.share.token == b.share.token }
    func hash(into h: inout Hasher) { h.combine(share.token) }
}
