import Foundation

/// Exposes the local MCP server on a public HTTPS URL with a Cloudflare quick tunnel, so cloud-hosted
/// AI apps (claude.ai connectors, ChatGPT connectors) can reach it. Uses the user's own `cloudflared`;
/// no Black Hole servers or accounts are involved.
@MainActor
@Observable
final class MCPTunnel {
    enum State: Equatable {
        case off
        case notInstalled
        case starting
        case running(URL)
        case failed(String)
    }

    private(set) var state: State = .off

    static let enabledKey = "mcp.remote.enabled"
    private static let pidKey = "mcp.remote.pid"

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

    static var cloudflaredPath: String? {
        let candidates = ["/opt/homebrew/bin/cloudflared", "/usr/local/bin/cloudflared", "/usr/bin/cloudflared"]
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
        guard let binary = Self.cloudflaredPath else {
            state = .notInstalled
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
