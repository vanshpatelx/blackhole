import CryptoKit
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
        case puzzleTooHard

        var errorDescription: String? {
            switch self {
            case let .http(status, body): "Enrollment failed (\(status)): \(body)"
            case .malformed: "The enrollment service sent something unexpected."
            case .puzzleTooHard: "Couldn't complete the enrollment check. Try again."
            }
        }
    }

    /// Asks for this install's address and tunnel token, reusing the stored one when possible.
    static func enroll() async throws -> Enrollment {
        if let stored {
            return stored
        }

        // Registering an address costs a small proof of work, so the service can't be farmed.
        let puzzle = try await fetchChallenge()
        let counter = try solve(nonce: puzzle.nonce, bits: puzzle.bits)

        var request = URLRequest(url: enrollmentAPI.appending(path: "v1/enroll"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "installId": installID,
            "nonce": puzzle.nonce,
            "counter": counter
        ])
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

    private struct Puzzle {
        let nonce: String
        let bits: Int
    }

    private static func fetchChallenge() async throws -> Puzzle {
        var request = URLRequest(url: enrollmentAPI.appending(path: "v1/challenge"))
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nonce = payload["nonce"] as? String,
              let bits = payload["bits"] as? Int
        else {
            throw EnrollError.http(status, "Couldn't start enrollment")
        }
        return Puzzle(nonce: nonce, bits: bits)
    }

    /// Finds a counter whose SHA-256 starts with `bits` zero bits. Around 2^bits hashes; 20 bits is
    /// a fraction of a second here and expensive for anyone registering addresses in bulk.
    private static func solve(nonce: String, bits: Int) throws -> Int {
        let prefix = "\(nonce):\(installID):"
        let ceiling = 1 << min(bits + 6, 30)
        for counter in 0 ..< ceiling {
            let digest = SHA256.hash(data: Data((prefix + String(counter)).utf8))
            if leadingZeroBits(digest) >= bits {
                return counter
            }
        }
        throw EnrollError.puzzleTooHard
    }

    private static func leadingZeroBits(_ digest: SHA256Digest) -> Int {
        var bits = 0
        for byte in digest {
            guard byte == 0 else { return bits + byte.leadingZeroBitCount }
            bits += 8
        }
        return bits
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
