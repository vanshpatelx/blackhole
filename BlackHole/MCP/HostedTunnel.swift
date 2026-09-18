import Foundation

/// Permanent public address for this install, e.g. `https://mcp-a7f3.getblackhole.app`.
///
/// The app asks Black Hole's enrollment API once for a Cloudflare Tunnel that belongs to this Mac,
/// then runs that tunnel itself. Requests go from the assistant to Cloudflare and straight down the
/// tunnel; they never pass through a Black Hole server.
enum HostedTunnel {
    /// Where the enrollment API lives. Empty until the service is deployed.
    static let enrollmentAPI = URL(string: "https://api.getblackhole.app")!

    struct Enrollment: Codable, Equatable {
        var installID: String
        var hostname: String
        var tunnelToken: String
    }

    private static let installIDKey = "mcp.hosted.installID"
    private static let enrollmentKey = "mcp.hosted.enrollment"

    /// Stable per-Mac id, so re-enrolling keeps the same address.
    static var installID: String {
        if let existing = UserDefaults.standard.string(forKey: installIDKey) {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installIDKey)
        return fresh
    }

    static var stored: Enrollment? {
        get {
            guard let data = UserDefaults.standard.data(forKey: enrollmentKey) else { return nil }
            return try? JSONDecoder().decode(Enrollment.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                UserDefaults.standard.removeObject(forKey: enrollmentKey)
                return
            }
            UserDefaults.standard.set(data, forKey: enrollmentKey)
        }
    }

    enum EnrollError: LocalizedError {
        case http(Int, String)
        case malformed

        var errorDescription: String? {
            switch self {
            case let .http(status, body): "Enrollment failed (\(status)): \(body)"
            case .malformed: "The enrollment service sent something unexpected."
            }
        }
    }

    /// Asks for this install's address and tunnel token, reusing the stored one when possible.
    static func enroll() async throws -> Enrollment {
        if let stored {
            return stored
        }

        var request = URLRequest(url: enrollmentAPI.appending(path: "v1/enroll"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["installId": installID])
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw EnrollError.http(status, String(decoding: data, as: UTF8.self).prefix(200).description)
        }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hostname = payload["hostname"] as? String,
              let token = payload["tunnelToken"] as? String
        else {
            throw EnrollError.malformed
        }

        let enrollment = Enrollment(installID: installID, hostname: hostname, tunnelToken: token)
        stored = enrollment
        return enrollment
    }

    /// Gives the address back so it can be reused by someone else, and forgets it locally.
    static func revoke() async {
        guard stored != nil else { return }
        var request = URLRequest(url: enrollmentAPI.appending(path: "v1/revoke"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["installId": installID])
        _ = try? await URLSession.shared.data(for: request)
        stored = nil
    }
}
