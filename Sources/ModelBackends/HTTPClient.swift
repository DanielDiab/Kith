import AgentCore
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The one network call a backend makes. Tests swap in a scripted client, so the tool loops
/// of both backends run in CI without a server.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    /// Callback API on purpose: it behaves the same on Apple platforms and on Linux.
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
                }
            }.resume()
        }
    }
}

enum HTTP {
    static func post(_ url: URL, json: JSONValue, headers: [String: String], client: any HTTPClient, timeout: TimeInterval) async throws -> JSONValue {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = Data(json.jsonString().utf8)
        let reply: (Data, Int)
        do {
            reply = try await client.send(request)
        } catch {
            throw BackendError.unavailable("\(url.host ?? url.absoluteString) is not reachable: \(error.localizedDescription)")
        }
        let (data, status) = reply
        let body = String(decoding: data, as: UTF8.self)
        switch status {
        case 200..<300:
            do { return try JSONValue.parse(body) } catch { throw BackendError.failed("unreadable response: \(body.prefix(200))") }
        case 429:
            throw BackendError.rateLimited
        case 400, 413:
            let lower = body.lowercased()
            if lower.contains("context") || lower.contains("too long") || lower.contains("too many tokens") {
                throw BackendError.contextExceeded
            }
            throw BackendError.failed("HTTP \(status): \(body.prefix(300))")
        case 401, 403:
            throw BackendError.unavailable("credentials rejected (HTTP \(status))")
        default:
            throw BackendError.failed("HTTP \(status): \(body.prefix(300))")
        }
    }

    static func get(_ url: URL, client: any HTTPClient, timeout: TimeInterval) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        guard let (_, status) = try? await client.send(request) else { return false }
        return (200..<300).contains(status)
    }
}
