import SwiftUI
import Observation

enum Tab: Hashable { case passport, health, share, activity }

/// App-wide state. Everything lives on the server; the app only remembers the server URL (spec §2).
@MainActor
@Observable
final class AppModel {
    static let defaultBaseURL = "http://localhost:3000"

    var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: "baseURL") }
    }
    var record: HealthRecord?
    var shares: [Share] = []
    var error: String?
    var isLoading = false
    var selectedTab: Tab = .passport
    var lastRefresh: Date?

    init() {
        baseURLString = UserDefaults.standard.string(forKey: "baseURL") ?? Self.defaultBaseURL
    }

    var api: API { API(baseURL: URL(string: baseURLString) ?? URL(string: Self.defaultBaseURL)!) }

    var isConnected: Bool { record?.source.connected ?? false }
    var activeShares: [Share] { shares.filter { $0.status == .active } }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let r = api.record()
            async let s = api.shares()
            (record, shares) = try await (r, s)
            lastRefresh = .now
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func connectSource() async throws {
        _ = try await api.connect()
        await refresh()
    }

    func createShare(categories: [Category], duration: ShareDuration, label: String) async throws -> CreateShareResponse {
        let res = try await api.createShare(categories: categories, durationHours: duration.rawValue, label: label)
        await refresh()
        return res
    }

    func revoke(_ share: Share) async throws {
        _ = try await api.revoke(token: share.token)
        await refresh()
    }

    func share(token: String) -> Share? { shares.first { $0.token == token } }
}
