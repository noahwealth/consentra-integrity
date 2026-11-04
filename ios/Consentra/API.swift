import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Thin client for the Consentra demo server (plan Task 1 JSON shapes).
struct API {
    let baseURL: URL

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    func record() async throws -> HealthRecord { try await get("api/record") }
    func connect() async throws -> SourceInfo { (try await send("api/source/connect", body: [String: String]()) as ConnectResponse).source }
    func shares() async throws -> [Share] { try await get("api/shares") }
    func revoke(token: String) async throws -> Share { try await send("api/shares/\(token)/revoke", body: [String: String]()) }

    func createShare(categories: [Category], durationHours: Int, label: String) async throws -> CreateShareResponse {
        struct Body: Encodable { let categories: [String]; let durationHours: Int; let label: String }
        return try await send("api/shares", body: Body(categories: categories.map(\.rawValue), durationHours: durationHours, label: label))
    }

    func passData(token: String) async throws -> Data {
        try await raw(URLRequest(url: baseURL.appending(path: "api/shares/\(token)/pass.pkpass")))
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try Self.decoder.decode(T.self, from: try await raw(URLRequest(url: baseURL.appending(path: path))))
    }

    private func send<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return try Self.decoder.decode(T.self, from: try await raw(req))
    }

    private func raw(_ req: URLRequest) async throws -> Data {
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await Self.session.data(for: req)
        } catch {
            throw APIError(message: "Can't reach the Consentra server at \(baseURL.absoluteString). Is it running?")
        }
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "Unexpected response") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError(message: msg ?? "Server error \(http.statusCode)")
        }
        return data
    }
}
