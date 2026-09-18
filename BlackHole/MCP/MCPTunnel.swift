import Foundation

/// Exposes the local MCP server on a public HTTPS URL with a Cloudflare quick tunnel, so cloud-hosted
/// AI apps (claude.ai connectors, ChatGPT connectors) can reach it. Uses the user's own `cloudflared`;
/// no Black Hole servers or accounts are involved.
@MainActor
@Observable
final class MCPTunnel {
    enum State: Equatable {
        case off
        /// Fetching the tunnel client the first time public access is switched on.
        case installing(Double)
        case starting
        case running(URL)
        case failed(String)
    }

    private(set) var state: State = .off {
        didSet { onStateChange?() }
    }
    /// Called whenever the public URL appears or goes away.
    @ObservationIgnored var onStateChange: (() -> Void)?

    /// How the public URL is created.
    enum Provider: String, CaseIterable, Identifiable, Codable {
        /// Permanent URL through the user's own tailnet. Preferred when Tailscale is set up.
        case tailscale
        /// Free Cloudflare quick tunnel: works anywhere, but the URL changes on every restart.
        case cloudflare

        var id: Self { self }
        var title: String { self == .tailscale ? "Tailscale Funnel (permanent URL)" : "Cloudflare quick tunnel (URL changes)" }
    }

    static let enabledKey = "mcp.remote.enabled"
    private static let providerKey = "mcp.remote.provider"
    private static let pidKey = "mcp.remote.pid"

    static var provider: Provider {
        get {
            if let raw = UserDefaults.standard.string(forKey: providerKey), let p = Provider(rawValue: raw) { return p }
            // Default to the permanent URL when Tailscale is available.
            return Tailscale.isAvailable ? .tailscale : .cloudflare
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var output = ""
    @ObservationIgnored private var restartWork: DispatchWorkItem?

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    var isActive: Bool {
        if case .running = state { return true }
        return false
    }

    init() {
        Self.killOrphan()
    }

    /// Black Hole's own copy first, then any the user installed themselves.
    static var cloudflaredPath: String? {
        let candidates = [TunnelInstaller.managedBinary.path, "/opt/homebrew/bin/cloudflared",
                          "/usr/local/bin/cloudflared", "/usr/bin/cloudflared"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Public URL a cloud connector should use; the token is part of the path because most connectors can't send headers.
    func connectorURL(token: String) -> URL? {
        guard case .running(let base) = state else { return nil }
        return base.appending(path: "mcp").appending(path: token)
    }

    func start(localPort: UInt16) {
        stop()
        UserDefaults.standard.set(true, forKey: Self.enabledKey)

        if Self.provider == .tailscale {
            guard Tailscale.isAvailable else {
                state = .failed("Tailscale isn't running or signed in.")
                return
            }
            state = .starting
            let port = localPort
            Task { @MainActor in
                guard let url = await Task.detached(priority: .userInitiated, operation: { Tailscale.startFunnel(port: port) }).value else {
                    self.state = .failed("Couldn't start Tailscale Funnel. Enable HTTPS and Funnel for this tailnet.")
                    return
                }
                NSLog("Black Hole remote MCP tunnel ready at %@", url.absoluteString)
                self.state = .running(url)
            }
            return
        }

        guard let binary = Self.cloudflaredPath else {
            // First run: fetch the tunnel client, then start.
            state = .installing(0)
            Task { @MainActor in
                do {
                    _ = try await TunnelInstaller.install { fraction in
                        Task { @MainActor in
                            if case .installing = self.state { self.state = .installing(fraction) }
                        }
                    }
                    guard Self.isEnabled else { return }
                    self.start(localPort: localPort)
                } catch {
                    self.state = .failed(error.localizedDescription)
                }
            }
            return
        }
        state = .starting
        output = ""

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:\(localPort)"]
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            Task { @MainActor in self?.consume(chunk) }
        }
        proc.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                self.process = nil
                UserDefaults.standard.removeObject(forKey: Self.pidKey)
                if Self.isEnabled {
                    self.state = .failed("Tunnel stopped. Retrying…")
                    self.scheduleRestart(localPort: localPort)
                }
            }
        }
        do {
            try proc.run()
            process = proc
            UserDefaults.standard.set(Int(proc.processIdentifier), forKey: Self.pidKey)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop(disable: Bool = false) {
        restartWork?.cancel()
        if disable { UserDefaults.standard.set(false, forKey: Self.enabledKey) }
        if Self.provider == .tailscale, Tailscale.isFunnelRunning { Tailscale.stopFunnel() }
        if let process, process.isRunning {
            self.process = nil
            process.terminate()
        }
        UserDefaults.standard.removeObject(forKey: Self.pidKey)
        state = .off
    }

    private func consume(_ chunk: String) {
        output += chunk
        if output.count > 20_000 { output = String(output.suffix(5_000)) }
        guard state == .starting else { return }
        if let range = output.range(of: #"https://[a-z0-9-]+\.trycloudflare\.com"#, options: .regularExpression),
           let url = URL(string: String(output[range])) {
            NSLog("Black Hole remote MCP tunnel ready at %@", url.absoluteString)
            state = .running(url)
        } else if output.contains("failed to request quick Tunnel") || output.contains("ERR ") && output.contains("quick Tunnel") {
            state = .failed("Cloudflare couldn't create a tunnel. Check your internet connection.")
        }
    }

    private func scheduleRestart(localPort: UInt16) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, Self.isEnabled, self.process == nil else { return }
                self.start(localPort: localPort)
            }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// A crash or force-quit can leave `cloudflared` running; stop the one we started last time.
    private static func killOrphan() {
        let pid = UserDefaults.standard.integer(forKey: pidKey)
        guard pid > 0 else { return }
        // Only signal it if it's still a cloudflared process.
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/bin/ps")
        check.arguments = ["-p", "\(pid)", "-o", "comm="]
        let pipe = Pipe()
        check.standardOutput = pipe
        try? check.run()
        check.waitUntilExit()
        let command = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if command.contains("cloudflared") { kill(pid_t(pid), SIGTERM) }
        UserDefaults.standard.removeObject(forKey: pidKey)
    }
}
