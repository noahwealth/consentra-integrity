import SwiftUI

/// Figma 10 · My Health, and 11/12 · category detail.
@MainActor
struct MyHealthView: View {
    @Environment(AppModel.self) private var model
    @State private var showConnect = false

    var body: some View {
        NavigationStack {
            Group {
                if let record = model.record, record.source.connected {
                    List {
                        if let error = model.error {
                            ErrorBanner(message: error) { await model.refresh() }
                                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        }
                        Section {
                            ForEach(Category.allCases) { c in
                                NavigationLink {
                                    CategoryDetailView(category: c, items: record.items(c))
                                } label: {
                                    HStack(spacing: 12) {
                                        CategoryIcon(category: c)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(c.title)
                                            Text(c.subtitle).font(.footnote).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(record.items(c).count)").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } footer: {
                            Text("From \(record.source.name), \(record.source.city) \(record.source.flag)")
                        }
                    }
                } else if let error = model.error {
                    ScrollView { ErrorBanner(message: error) { await model.refresh() }.padding(16) }
                } else if model.record == nil {
                    ProgressView()
                } else {
                    ContentUnavailableView {
                        Label("No records yet", systemImage: "heart.text.square")
                    } description: {
                        Text("Connect your home hospital to bring your history with you.")
                    } actions: {
                        Button("Connect Records") { showConnect = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("My Health")
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showConnect) { ConnectFlow() }
        }
    }
}

@MainActor
struct CategoryDetailView: View {
    let category: Category
    let items: [DisplayItem]

    var body: some View {
        List {
            if category == .labs {
                Section {
                    Label("Original UK units, with US conventional units", systemImage: "arrow.left.arrow.right")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(items) { item in RecordItemRow(category: category, item: item) }
            }
        }
        .navigationTitle(category.title)
    }
}

@MainActor
struct RecordItemRow: View {
    let category: Category
    let item: DisplayItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.body.weight(.medium))
                    .foregroundStyle(isSevereAllergy ? .red : .primary)
                if !item.detail.isEmpty {
                    Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let v = item.value, let unit = item.unit {
                    Text("\(formatNumber(v)) \(unit)").font(.body.weight(.semibold)).monospacedDigit()
                }
                if let us = item.usValue, let usUnit = item.usUnit {
                    Text("US \(formatNumber(us)) \(usUnit)").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                if item.date != nil {
                    Text(shortDate(item.date)).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var isSevereAllergy: Bool { category == .allergies && item.detail.localizedCaseInsensitiveContains("severe") }
}
