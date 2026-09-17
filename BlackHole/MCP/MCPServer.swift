import Foundation
import Network

/// Shared settings for the local MCP endpoint. The app writes them to a file readable only by
/// this user so the bundled `blackhole-mcp` bridge can find the port and token.
struct MCPConfig: Codable, Equatable {
    var enabled: Bool
    var port: UInt16
    var token: String

    static let enabledKey = "mcp.enabled"
    static let defaultPort: UInt16 = 52_321

    static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Black Hole/mcp.json")
    }

    var endpoint: String { "http://127.0.0.1:\(port)/mcp" }

    static func load() -> MCPConfig? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(MCPConfig.self, from: data)
    }

    func save() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Minimal HTTP/1.1 server on 127.0.0.1 implementing MCP's Streamable HTTP transport with plain JSON
/// responses (no SSE streams, no sessions), which every current MCP client supports.
@MainActor
@Observable
final class MCPServer {
    enum State: Equatable {
        case off
        case running(port: UInt16)
        case failed(String)
    }

    private(set) var state: State = .off
    private(set) var config: MCPConfig

    @ObservationIgnored private let router: MCPRouter
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private let queue = DispatchQueue(label: "app.getblackhole.mcp")

    init(router: MCPRouter, allowStart: Bool = true) {
        self.router = router
        let stored = MCPConfig.load()
        config = MCPConfig(
            enabled: UserDefaults.standard.bool(forKey: MCPConfig.enabledKey),
            port: stored?.port ?? MCPConfig.defaultPort,
            token: stored?.token ?? MCPConfig.newToken())
        guard allowStart else { return }
        config.save()
        if config.enabled { start() }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: MCPConfig.enabledKey)
        config.enabled = enabled
        config.save()
        enabled ? start() : stop()
    }

    func regenerateToken() {
        config.token = MCPConfig.newToken()
        config.save()
    }

    /// Path of the stdio bridge inside the app bundle.
    var bridgePath: String {
        Bundle.main.bundleURL.appending(path: "Contents/MacOS/blackhole-mcp").path
    }

    enum Client: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case cursor = "Cursor"
        case claudeDesktop = "Claude Desktop"
        var id: Self { self }
    }

    /// Ready-to-paste setup for each client.
    func snippet(for client: Client) -> String {
        switch client {
        case .claudeCode:
            return "claude mcp add --transport http black-hole \(config.endpoint) --header \"Authorization: Bearer \(config.token)\""
        case .cursor:
            return """
                {
                  "mcpServers": {
                    "black-hole": {
                      "url": "\(config.endpoint)",
                      "headers": { "Authorization": "Bearer \(config.token)" }
                    }
                  }
                }
                """
        case .claudeDesktop:
            return """
                {
                  "mcpServers": {
                    "black-hole": {
                      "command": "\(bridgePath)"
                    }
                  }
                }
                """
        }
    }

    private func start(tryPort: UInt16? = nil, attemptsLeft: Int = 5) {
        stop()
        let port = tryPort ?? config.port
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] newState in
                Task { @MainActor in
                    guard let self else { return }
                    switch newState {
                    case .ready:
                        if self.config.port != port {
                            self.config.port = port
                            self.config.save()
                        }
                        self.state = .running(port: port)
                    case .failed(let error), .waiting(let error):
                        // `.waiting` is how a busy port usually shows up; treat it as a failure.
                        self.listener?.cancel()
                        if attemptsLeft > 0 {
                            // Port busy: try the next one and remember whichever works.
                            self.start(tryPort: port &+ 1, attemptsLeft: attemptsLeft - 1)
                        } else {
                            self.state = .failed(error.localizedDescription)
                        }
                    default:
                        break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        state = .off
    }

    // MARK: Connections

    nonisolated private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    nonisolated private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var data = buffer
            if let chunk { data.append(chunk) }

            if let request = HTTPRequest(data) {
                Task { @MainActor in
                    let response = self.respond(to: request)
                    connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
                }
            } else if isComplete || error != nil || data.count > 4 << 20 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: data)
            }
        }
    }

    private func respond(to request: HTTPRequest) -> HTTPResponse {
        // Browsers send Origin; only allow local pages so a website can't drive the user's planner.
        if let origin = request.headers["origin"], !(origin.hasPrefix("http://localhost") || origin.hasPrefix("http://127.0.0.1")) {
            return HTTPResponse(status: 403, body: Data("Forbidden origin".utf8))
        }
        guard request.path == "/mcp" || request.path.hasPrefix("/mcp?") else {
            return HTTPResponse(status: 404, body: Data("Not found".utf8))
        }
        guard request.headers["authorization"] == "Bearer \(config.token)" else {
            return HTTPResponse(status: 401, body: Data("Missing or invalid token. Copy the config from Black Hole Settings.".utf8))
        }
        switch request.method {
        case "POST":
            guard let reply = router.handle(request.body) else { return HTTPResponse(status: 202, body: Data()) }
            return HTTPResponse(status: 200, contentType: "application/json", body: reply)
        case "DELETE":
            return HTTPResponse(status: 200, body: Data())
        default:
            // No server-initiated streams.
            return HTTPResponse(status: 405, headers: ["Allow": "POST, DELETE"], body: Data())
        }
    }
}

// MARK: HTTP plumbing

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// Parses a complete request, or returns `nil` if more bytes are needed.
    init?(_ data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return nil }

        method = String(requestLine[0]).uppercased()
        path = String(requestLine[1])
        self.headers = headers
        body = data.subdata(in: bodyStart..<(bodyStart + length))
    }
}

struct HTTPResponse {
    var status: Int
    var contentType = "text/plain; charset=utf-8"
    var headers: [String: String] = [:]
    var body: Data

    func serialized() -> Data {
        let reason = [200: "OK", 202: "Accepted", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (key, value) in headers { head += "\(key): \(value)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}
