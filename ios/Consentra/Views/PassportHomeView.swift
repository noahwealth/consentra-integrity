import SwiftUI

/// Figma 09 · Passport Home
@MainActor
struct PassportHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showConnect = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = model.error {
                        ErrorBanner(message: error) { await model.refresh() }
                    }
                    if model.record != nil && !model.isConnected {
                        connectCTA
                    }
                    PassportCard(record: model.record)
                    statsRow
                    actions
                    if let source = model.record?.source, source.connected {
                        sourcesSection(source)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Passport")
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showConnect = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Connect records")
                    Button { showSettings = true } label: {
                        Text(model.record?.patient.initials ?? "ND")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.gray.gradient, in: Circle())
                    }
                    .accessibilityLabel("Profile and settings")
                }
            }
            .sheet(isPresented: $showConnect) { ConnectFlow() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var connectCTA: some View {
        Button { showConnect = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "link.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your records").font(.headline)
                    Text("Bring your history from home so US doctors can see it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.connect")
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(title: "Records", value: "\(model.record?.totalCount ?? 0)")
            StatTile(title: "Sources", value: model.isConnected ? "1" : "0")
            StatTile(title: "Active Access", value: "\(model.activeShares.count)")
        }
    }

    private var actions: some View {
        GroupCard {
            ActionRow(symbol: "heart.fill", tint: .pink, title: "View My Health") { model.selectedTab = .health }
            Divider().padding(.leading, 60)
            ActionRow(symbol: "square.and.arrow.up.fill", tint: .blue, title: "Share My Health") { model.selectedTab = .share }
            Divider().padding(.leading, 60)
            NavigationLink { AccessListView() } label: {
                ActionRowLabel(symbol: "key.fill", tint: .orange, title: "Manage Access",
                               trailing: model.activeShares.isEmpty ? nil : "\(model.activeShares.count)")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.manageAccess")
        }
    }

    private func sourcesSection(_ source: SourceInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Connected Sources")
            GroupCard {
                HStack(spacing: 12) {
                    Text(source.flag).font(.title)
                        .frame(width: 40, height: 40)
                        .background(Color(.tertiarySystemFill), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name).font(.body.weight(.medium))
                        Text("\(model.record?.totalCount ?? 0) records · \(source.city), \(source.country)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .padding(14)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("home.source")
            }
        }
    }
}

@MainActor
struct PassportCard: View {
    let record: HealthRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ConsentraMark(size: 26)
                Text("Consentra").font(.title3.weight(.semibold))
                Spacer()
                Text(record?.patient.homeCountry == "United Kingdom" ? "🇬🇧 → 🇺🇸" : "")
                    .font(.subheadline)
            }
            Spacer(minLength: 28)
            Text("HEALTH PASSPORT")
                .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
            Text(record?.patient.name ?? " ")
                .font(.system(size: 30, weight: .bold))
                .redacted(reason: record == nil ? .placeholder : [])
            Spacer(minLength: 28)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let s = record?.source, s.connected {
                        Text("1 source connected")
                        if let synced = s.lastSynced { Text("Updated \(synced.relative)") }
                    } else {
                        Text("No sources connected yet")
                    }
                }
                .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if let s = record?.source, s.connected {
                    Text(s.flag).font(.title3)
                        .frame(width: 30, height: 30)
                        .background(.white, in: Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.06)))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
        .background(Theme.cardWash, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.indigo.opacity(0.12)))
        .shadow(color: Theme.indigo.opacity(0.15), radius: 18, y: 8)
        .environment(\.colorScheme, .light)
    }
}

@MainActor
struct StatTile: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            Text(value).font(.title2.weight(.semibold)).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

@MainActor
struct ActionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var trailing: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) { ActionRowLabel(symbol: symbol, tint: tint, title: title, trailing: trailing) }
            .buttonStyle(.plain)
    }
}

@MainActor
struct ActionRowLabel: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
            if let trailing { Text(trailing).foregroundStyle(.secondary) }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
