import SwiftUI

/// The five shareable record categories. Raw values match the server (decision.md / plan Global Constraints).
enum Category: String, CaseIterable, Codable, Identifiable, Hashable {
    case medications, allergies, conditions, labs, immunizations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .medications: "Medications"
        case .allergies: "Allergies"
        case .conditions: "Conditions"
        case .labs: "Lab Results"
        case .immunizations: "Immunizations"
        }
    }

    var subtitle: String {
        switch self {
        case .medications: "Current and past medications"
        case .allergies: "Allergies and adverse reactions"
        case .conditions: "Diagnoses and problem list"
        case .labs: "Recent lab results, with US units"
        case .immunizations: "Vaccination history"
        }
    }

    var symbol: String {
        switch self {
        case .medications: "pills.fill"
        case .allergies: "exclamationmark.shield.fill"
        case .conditions: "heart.text.square.fill"
        case .labs: "flask.fill"
        case .immunizations: "syringe.fill"
        }
    }

    /// Tile colours taken from the Figma category icons.
    var tint: Color {
        switch self {
        case .medications: Color(red: 0.06, green: 0.49, blue: 0.53)
        case .allergies: Color(red: 0.80, green: 0.27, blue: 0.08)
        case .conditions: Color(red: 0.88, green: 0.14, blue: 0.37)
        case .labs: Color(red: 0.35, green: 0.34, blue: 0.84)
        case .immunizations: Color(red: 0.20, green: 0.66, blue: 0.33)
        }
    }
}

struct DisplayItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let date: String?
    let value: Double?
    let unit: String?
    let usValue: Double?
    let usUnit: String?
}

struct Patient: Codable, Hashable {
    let name: String
    let birthDate: String
    let homeCountry: String
    let nhsNumber: String?

    var initials: String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }
}

struct SourceInfo: Codable, Hashable {
    let id: String
    let name: String
    let city: String
    let country: String
    let flag: String
    let connected: Bool
    let lastSynced: Date?
}

struct HealthRecord: Codable {
    let patient: Patient
    let source: SourceInfo
    let categories: [String: [DisplayItem]]
    /// Whether the server can sign Wallet passes (certs installed). Missing on older servers → false.
    let walletAvailable: Bool

    enum CodingKeys: String, CodingKey { case patient, source, categories, walletAvailable }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        patient = try c.decode(Patient.self, forKey: .patient)
        source = try c.decode(SourceInfo.self, forKey: .source)
        categories = try c.decode([String: [DisplayItem]].self, forKey: .categories)
        walletAvailable = try c.decodeIfPresent(Bool.self, forKey: .walletAvailable) ?? false
    }

    func items(_ category: Category) -> [DisplayItem] { categories[category.rawValue] ?? [] }
    var totalCount: Int { categories.values.reduce(0) { $0 + $1.count } }
}

struct ShareViewEvent: Codable, Hashable {
    let at: Date
    let userAgent: String

    /// Rough, human label for the device that opened the link.
    var deviceLabel: String {
        let ua = userAgent.lowercased()
        if ua.contains("iphone") { return "iPhone" }
        if ua.contains("ipad") { return "iPad" }
        if ua.contains("android") { return "Android" }
        if ua.contains("macintosh") { return "Mac" }
        if ua.contains("windows") { return "Windows PC" }
        return "Browser"
    }
}

enum ShareStatus: String, Codable, Hashable {
    case active, expired, revoked

    var label: String {
        switch self {
        case .active: "Active"
        case .expired: "Expired"
        case .revoked: "Revoked"
        }
    }
}

struct Share: Codable, Identifiable, Hashable {
    let token: String
    let label: String
    let categories: [Category]
    let createdAt: Date
    let expiresAt: Date
    let revokedAt: Date?
    let status: ShareStatus
    let url: URL
    let views: [ShareViewEvent]

    var id: String { token }
    var displayLabel: String { label.isEmpty ? "Any clinician" : label }
}

struct CreateShareResponse: Codable {
    let share: Share
    let walletAvailable: Bool
}

struct ConnectResponse: Codable {
    let source: SourceInfo
    let counts: [String: Int]
}

/// Duration options, matching the server's allowed `durationHours`.
enum ShareDuration: Int, CaseIterable, Identifiable {
    case oneHour = 1, oneDay = 24, oneWeek = 168, thirtyDays = 720
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .oneHour: "1 hour"
        case .oneDay: "24 hours"
        case .oneWeek: "7 days"
        case .thirtyDays: "30 days"
        }
    }
    var short: String {
        switch self {
        case .oneHour: "1 h"
        case .oneDay: "24 h"
        case .oneWeek: "7 d"
        case .thirtyDays: "30 d"
        }
    }
}

/// One line in the Activity timeline (Figma 26), derived from shares.
struct ActivityEvent: Identifiable, Hashable {
    enum Kind: Hashable { case created, viewed, revoked }
    let id: String
    let kind: Kind
    let date: Date
    let shareToken: String
    let shareLabel: String
    let categories: [Category]
    var device: String? = nil

    static func from(shares: [Share]) -> [ActivityEvent] {
        var events: [ActivityEvent] = []
        for s in shares {
            events.append(.init(id: "\(s.token)-c", kind: .created, date: s.createdAt, shareToken: s.token, shareLabel: s.displayLabel, categories: s.categories))
            for (i, v) in s.views.enumerated() {
                events.append(.init(id: "\(s.token)-v\(i)", kind: .viewed, date: v.at, shareToken: s.token, shareLabel: s.displayLabel, categories: s.categories, device: v.deviceLabel))
            }
            if let r = s.revokedAt {
                events.append(.init(id: "\(s.token)-r", kind: .revoked, date: r, shareToken: s.token, shareLabel: s.displayLabel, categories: s.categories))
            }
        }
        return events.sorted { $0.date > $1.date }
    }
}
