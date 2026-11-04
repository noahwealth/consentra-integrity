import SwiftUI

/// Figma 27 (subset) · Profile & Settings: patient info and the demo server URL (decision.md D8).
@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var checking = false
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                if let p = model.record?.patient {
                    Section("Patient") {
                        LabeledContent("Name", value: p.name)
                        LabeledContent("Date of birth", value: shortDate(p.birthDate))
                        LabeledContent("Home country", value: p.homeCountry)
                        if let nhs = p.nhsNumber { LabeledContent("NHS number", value: nhs) }
                    }
                }
                Section {
                    TextField("http://192.168.1.10:3000", text: $draft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use this Mac (Simulator)") { draft = AppModel.defaultBaseURL }
                    Button {
                        Task { await save() }
                    } label: {
                        HStack { Text("Save & test connection"); Spacer(); if checking { ProgressView() } }
                    }
                    .disabled(checking || URL(string: draft) == nil)
                    if let result { Text(result).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Demo server")
                } footer: {
                    Text("On a real iPhone, enter the address the server prints at startup, e.g. http://10.0.0.5:3000.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { draft = model.baseURLString }
        }
    }

    @MainActor
    private func save() async {
        checking = true
        model.baseURLString = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        await model.refresh()
        result = model.error ?? "Connected ✓"
        checking = false
    }
}
