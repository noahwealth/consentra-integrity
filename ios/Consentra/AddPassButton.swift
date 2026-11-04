import SwiftUI
import PassKit

/// Apple's own "Add to Apple Wallet" button (required styling for Wallet).
struct AddPassButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) { context.coordinator.action = action }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

/// Presents Wallet's own "Add pass" sheet.
struct AddPassesSheet: UIViewControllerRepresentable {
    let pass: PKPass

    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(pass: pass) ?? UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// Fetches the signed pass for a share and drives the Wallet sheet.
@MainActor
struct WalletAddControl: View {
    @Environment(AppModel.self) private var model
    let share: Share
    @State private var pass: PKPass?
    @State private var loading = false
    @State private var error: String?

    private var alreadyInWallet: Bool {
        PKPassLibrary().passes().contains { $0.serialNumber == share.token }
    }

    var body: some View {
        VStack(spacing: 6) {
            if alreadyInWallet {
                Label("Added to Apple Wallet", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(height: 50)
            } else {
                ZStack {
                    AddPassButton { Task { await load() } }
                        .frame(height: 50)
                        .opacity(loading ? 0.4 : 1)
                    if loading { ProgressView() }
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
        }
        .sheet(isPresented: Binding(get: { pass != nil }, set: { if !$0 { pass = nil } })) {
            if let pass { AddPassesSheet(pass: pass).ignoresSafeArea() }
        }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let data = try await model.api.passData(token: share.token)
            pass = try PKPass(data: data)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
