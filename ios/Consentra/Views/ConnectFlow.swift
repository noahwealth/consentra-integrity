import SwiftUI

/// Figma 22–25 · Connect Records → Provider Sign-In → Authorize → Source Connected.
/// The sign-in is a fake approval (decision.md D9); "Allow" calls POST /api/source/connect.
@MainActor
struct ConnectFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []

    enum Step: Hashable { case signIn, authorize, connected }

    var body: some View {
        NavigationStack(path: $path) {
            ConnectListView(alreadyConnected: model.isConnected) { path.append(.signIn) }
                .navigationTitle("Connect Records")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { CloseButton { dismiss() } } }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .signIn: ProviderSignInView { path.append(.authorize) }
                    case .authorize: AuthorizeView { path.append(.connected) }
                    case .connected: SourceConnectedView { dismiss() }
                    }
                }
        }
    }
}

@MainActor
struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .accessibilityLabel("Close")
    }
}

@MainActor
private struct ConnectListView: View {
    let alreadyConnected: Bool
    let onSelect: () -> Void
    @State private var query = ""

    private let comingSoon: [(String, String, String)] = [
        ("Lakeshore Health Network", "Toronto", "🇨🇦"),
        ("Clínica San Marco", "Madrid", "🇪🇸"),
        ("Harbour City Medical Centre", "Sydney", "🇦🇺"),
        ("Rheinpark Klinikum", "Cologne", "🇩🇪"),
    ]

    var body: some View {
        List {
            Section {
                Button(action: onSelect) {
                    HStack(spacing: 12) {
                        HospitalBadge(initials: "TG", color: Color(red: 0.0, green: 0.37, blue: 0.72))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Thameside General Hospital").foregroundStyle(.primary)
                            Text("🇬🇧 London · Patient Portal").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if alreadyConnected {
                            Text("Connected").font(.footnote).foregroundStyle(.secondary)
                            Image(systemName: "checkmark").foregroundStyle(.green)
                        } else {
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .disabled(alreadyConnected)
                .accessibilityIdentifier("connect.thameside")
            } header: {
                Text("Your home health system")
            } footer: {
                Text("Records arrive in English with original units. Consentra adds US unit conversions for your doctors here.")
            }

            Section("Coming soon") {
                ForEach(comingSoon, id: \.0) { name, city, flag in
                    HStack(spacing: 12) {
                        HospitalBadge(initials: String(name.prefix(1)), color: .gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                            Text("\(flag) \(city)").font(.footnote)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your health system")
    }
}

@MainActor
struct HospitalBadge: View {
    let initials: String
    let color: Color
    var size: CGFloat = 40
    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

@MainActor
private struct ProviderSignInView: View {
    let onContinue: () -> Void
    @State private var nhsNumber = "999 123 4567"
    @State private var dob = "12/04/1988"
    @State private var working = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    HospitalBadge(initials: "TG", color: Color(red: 0.0, green: 0.37, blue: 0.72), size: 64)
                    Text("Thameside General Hospital").font(.title3.weight(.semibold))
                    Text("Patient Portal sign-in").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent("NHS number") { TextField("NHS number", text: $nhsNumber).multilineTextAlignment(.trailing) }
                LabeledContent("Date of birth") { TextField("DD/MM/YYYY", text: $dob).multilineTextAlignment(.trailing) }
            } footer: {
                Text("Demo: this is a simulated hospital portal. No real credentials are sent.")
            }
            Section {
                Button {
                    working = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { working = false; onContinue() }
                } label: {
                    HStack { Spacer(); if working { ProgressView() } else { Text("Sign in").bold() }; Spacer() }
                }
                .disabled(working)
            }
        }
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
private struct AuthorizeView: View {
    @Environment(AppModel.self) private var model
    let onAllowed: () -> Void
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            HospitalBadge(initials: "TG", color: Color(red: 0.0, green: 0.37, blue: 0.72), size: 52)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            ConsentraMark(size: 52)
                        }
                        Text("Allow Consentra to read your records?")
                            .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                        Text("Thameside General will share a read-only copy with your Health Passport. They won't see who you share it with.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("Consentra will be able to read") {
                    ForEach(Category.allCases) { c in
                        HStack(spacing: 12) {
                            CategoryIcon(category: c)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.title)
                                Text(c.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            VStack(spacing: 10) {
                Button {
                    Task {
                        working = true; error = nil
                        do { try await model.connectSource(); onAllowed() } catch { self.error = error.localizedDescription }
                        working = false
                    }
                } label: {
                    Group { if working { ProgressView().tint(.white) } else { Text("Allow").bold() } }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(working)
                Text("Read-only · You can disconnect at any time").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.bar)
        }
        .navigationTitle("Authorize")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
private struct SourceConnectedView: View {
    @Environment(AppModel.self) private var model
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: true)
            Text("Thameside General connected").font(.title2.weight(.bold)).multilineTextAlignment(.center)
            Text("\(model.record?.totalCount ?? 0) records added to your Health Passport.")
                .foregroundStyle(.secondary)
            GroupCard {
                ForEach(Category.allCases) { c in
                    HStack(spacing: 12) {
                        CategoryIcon(category: c, size: 26)
                        Text(c.title)
                        Spacer()
                        Text("\(model.record?.items(c).count ?? 0)").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            Spacer()
            Button(action: onDone) { Text("Done").bold().frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
        }
        .padding(16)
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden()
    }
}
