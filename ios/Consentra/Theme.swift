import SwiftUI

enum Theme {
    static let sky = Color(red: 0.35, green: 0.78, blue: 0.98)
    static let indigo = Color(red: 0.35, green: 0.34, blue: 0.84)
    static let violet = Color(red: 0.69, green: 0.32, blue: 0.87)
    static let gradient = LinearGradient(colors: [sky, indigo, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Soft card tint used on the passport card (Figma 09).
    static let cardWash = LinearGradient(
        colors: [Color.white, Color(red: 0.93, green: 0.92, blue: 1.0), Color(red: 0.89, green: 0.90, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The Consentra mark: gradient tile with an open white ring.
struct ConsentraMark: View {
    var size: CGFloat = 28
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Theme.gradient)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(.white, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                    .frame(width: size * 0.5, height: size * 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// Coloured rounded-square icon for a record category (Figma 05/16).
struct CategoryIcon: View {
    let category: Category
    var size: CGFloat = 30
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(category.tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Inline error with Retry. Used everywhere the server might be unreachable (plan Review Focus 5).
struct ErrorBanner: View {
    let message: String
    let retry: () async -> Void
    @State private var retrying = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.subheadline)
                Button {
                    Task { retrying = true; await retry(); retrying = false }
                } label: {
                    if retrying { ProgressView() } else { Text("Retry").bold() }
                }
                .disabled(retrying)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A white grouped card, like an inset-grouped list section.
struct GroupCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

extension Date {
    var relative: String { RelativeDateTimeFormatter().localizedString(for: self, relativeTo: .now) }
}

/// "in 23 h 59 min" / "in 6 d 4 h" style countdown.
func countdown(to date: Date, now: Date = .now) -> String {
    let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
    let h = minutes / 60, d = h / 24
    if d >= 1 { return "\(d) d \(h % 24) h" }
    if h >= 1 { return "\(h) h \(minutes % 60) min" }
    return "\(minutes) min"
}

/// "22 Sep 2026": unambiguous for UK and US readers.
func shortDate(_ iso: String?) -> String {
    guard let iso else { return "" }
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.dateFormat = "yyyy-MM-dd"
    parser.timeZone = TimeZone(identifier: "UTC")
    guard let d = parser.date(from: String(iso.prefix(10))) else { return iso }
    let out = DateFormatter()
    out.dateFormat = "d MMM yyyy"
    out.timeZone = TimeZone(identifier: "UTC")
    return out.string(from: d)
}

func formatNumber(_ v: Double) -> String {
    v.rounded() == v ? String(Int(v)) : String(format: "%g", v)
}
