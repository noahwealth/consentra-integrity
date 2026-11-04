import SwiftUI

/// Figma 19 · Present to Provider: QR, countdown, Add to Apple Wallet, share link.
@MainActor
struct PresentView: View {
    @Environment(AppModel.self) private var model
    let share: Share
    let walletAvailable: Bool

    /// Live status from the model, so a revoke elsewhere is reflected here.
    private var current: Share { model.share(token: share.token) ?? share }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Present to Provider").font(.title.weight(.bold))
                    Text("Have your provider scan this code. It opens your shared record in their browser. Nothing to install.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                qrCard

                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    VStack(spacing: 4) {
                        if current.status == .active {
                            Text("Expires in \(countdown(to: current.expiresAt, now: ctx.date))")
                                .font(.subheadline.weight(.medium))
                        } else {
                            Label(current.status == .revoked ? "Access revoked" : "Expired", systemImage: "lock.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                        }
                        Text("For \(current.displayLabel)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                sharingChips

                VStack(spacing: 10) {
                    if walletAvailable && current.status == .active {
                        WalletAddControl(share: current)
                    }
                    ShareLink(item: current.url, subject: Text("My shared health record"),
                              message: Text("Read-only link to my health record. It expires automatically.")) {
                        Text("Share Link Instead").font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    .disabled(current.status != .active)
                    NavigationLink { AccessDetailView(token: current.token) } label: {
                        Text("Manage this share").font(.subheadline)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var qrCard: some View {
        ZStack {
            if let img = QR.image(for: current.url.absoluteString) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
                    .opacity(current.status == .active ? 1 : 0.15)
                    .accessibilityLabel("QR code for your shared record")
            }
            if current.status == .active {
                ConsentraMark(size: 44)
                    .padding(5)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 260, height: 260)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
    }

    private var sharingChips: some View {
        VStack(spacing: 8) {
            Text("SHARING").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            FlowChips(categories: current.categories)
        }
    }
}

/// Simple wrapping row of category chips.
struct FlowChips: View {
    let categories: [Category]
    var body: some View {
        ViewThatFits {
            HStack(spacing: 6) { chips }
            VStack(spacing: 6) {
                HStack(spacing: 6) { ForEach(categories.prefix(3)) { chip($0) } }
                HStack(spacing: 6) { ForEach(categories.dropFirst(3)) { chip($0) } }
            }
        }
    }
    private var chips: some View { ForEach(categories) { chip($0) } }
    private func chip(_ c: Category) -> some View {
        Label(c.title, systemImage: c.symbol)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(c.tint)
            .background(c.tint.opacity(0.12), in: Capsule())
    }
}
