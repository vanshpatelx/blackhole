import Foundation

/// Thin wrapper around the `tailscale` CLI. Tailscale gives Black Hole two things a quick tunnel can't:
/// a permanent public URL (Funnel) and direct, private access from the user's other machines (tailnet).
enum Tailscale {
    static var cliPath: String? {
        let candidates = [
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    static func run(_ arguments: [String], timeout: TimeInterval = 8) -> String? {
        guard let cliPath else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cliPath)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline { usleep(50_000) }
        if proc.isRunning { proc.terminate() }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// This Mac's tailnet address, when Tailscale is running and logged in.
    static var ipv4: String? {
        guard let output = run(["ip", "-4"]), !output.isEmpty else { return nil }
        let first = output.components(separatedBy: .newlines).first ?? ""
        return first.hasPrefix("100.") ? first : nil
    }

    /// MagicDNS name, e.g. "vanshs-macbook-pro.taild5f9c6.ts.net".
    static var dnsName: String? {
        guard let json = run(["status", "--json"]), let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sel = root["Self"] as? [String: Any],
              let name = sel["DNSName"] as? String, !name.isEmpty else { return nil }
        return name.hasSuffix(".") ? String(name.dropLast()) : name
    }

    static var isAvailable: Bool { dnsName != nil }

    /// Serves the local port on a public HTTPS URL that never changes.
    static func startFunnel(port: UInt16) -> URL? {
        _ = run(["funnel", "--bg", "\(port)"], timeout: 20)
        guard let dnsName else { return nil }
        return URL(string: "https://\(dnsName)")
    }

    static func stopFunnel() {
        _ = run(["funnel", "--https=443", "off"], timeout: 15)
    }

    static var isFunnelRunning: Bool {
        guard let status = run(["funnel", "status"]) else { return false }
        return status.contains("Funnel on")
    }
}
