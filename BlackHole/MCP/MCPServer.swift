import Foundation
import Network

/// Settings for the MCP endpoint, written to a file readable only by this user so scripts and
/// agents can discover the current URLs.
struct MCPConfig: Codable, Equatable {
    var enabled: Bool
    var port: UInt16
    var token: String
    /// Current public connector URL, if remote access is on. Written out so other tools can find it.
    var remoteURL: String?
    /// Address other machines on the user's tailnet can use.
    var tailnetURL: String?

    static let enabledKey = "mcp.enabled"
    static let defaultPort: UInt16 = 52321

    static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Black Hole/mcp.json")
    }

    var endpoint: String {
        "http://127.0.0.1:\(port)/mcp"
    }

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

    /// Public tunnel for cloud-hosted AI apps.
    let tunnel = MCPTunnel()

    @ObservationIgnored private let router: MCPRouter
    @ObservationIgnored private var listener: NWListener?
    /// Second listener bound to this Mac's tailnet address, so the user's other machines can connect.
    @ObservationIgnored private var tailnetListener: NWListener?
    private(set) var tailnetAddress: String?
    @ObservationIgnored private let queue = DispatchQueue(label: "app.getblackhole.mcp")

    init(router: MCPRouter, allowStart: Bool = true) {
        self.router = router
        let stored = MCPConfig.load()
        config = MCPConfig(
            enabled: UserDefaults.standard.bool(forKey: MCPConfig.enabledKey),
            port: stored?.port ?? MCPConfig.defaultPort,
            token: stored?.token ?? MCPConfig.newToken()
        )
        tunnel.onStateChange = { [weak self] in self?.publishURLs() }
        guard allowStart else { return }
        config.save()
        if config.enabled {
            start()
            if isTailnetEnabled {
                startTailnetListener()
            }
            if MCPTunnel.isEnabled {
                tunnel.start(localPort: config.port)
            }
        }
    }

    func setRemoteAccess(_ on: Bool) {
        if on {
            tunnel.start(localPort: config.port)
        } else {
            tunnel.stop(disable: true)
        }
    }

    func setRemoteProvider(_ provider: MCPTunnel.Provider) {
        MCPTunnel.provider = provider
        if MCPTunnel.isEnabled {
            tunnel.start(localPort: config.port)
        }
    }

    /// Public URL to paste into claude.ai or ChatGPT connectors, when the tunnel is up.
    var connectorURL: URL? {
        tunnel.connectorURL(token: config.token)
    }

    /// Single switch: the MCP endpoint and the public URL that web assistants need.
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: MCPConfig.enabledKey)
        config.enabled = enabled
        config.save()
        setRemoteAccess(enabled)
        if enabled {
            start()
            if isTailnetEnabled {
                startTailnetListener()
            }
        } else {
            stop()
            stopTailnetListener()
        }
    }

    func regenerateToken() {
        config.token = MCPConfig.newToken()
        publishURLs()
    }

    static let tailnetKey = "mcp.tailnet.enabled"
    var isTailnetEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.tailnetKey)
    }

    func setTailnetAccess(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.tailnetKey)
        if on {
            startTailnetListener()
        } else {
            stopTailnetListener()
        }
    }

    /// URL for machines on the same tailnet (private, permanent, no public exposure).
    var tailnetURL: URL? {
        guard let tailnetAddress else { return nil }
        return URL(string: "http://\(tailnetAddress):\(config.port)/mcp/\(config.token)")
    }

    /// Keeps mcp.json in step with the current URLs.
    func publishURLs() {
        config.remoteURL = connectorURL?.absoluteString
        config.tailnetURL = tailnetURL?.absoluteString
        config.save()
    }

    private func startTailnetListener() {
        stopTailnetListener()
        guard let ip = Tailscale.ipv4 else { return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: config.port)!)
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self] newState in
                Task { @MainActor in
                    guard let self else { return }
                    if case .ready = newState {
                        self.tailnetAddress = ip
                        self.publishURLs()
                    }
                }
            }
            tailnetListener = listener
            listener.start(queue: queue)
        } catch {
            tailnetAddress = nil
        }
    }

    private func stopTailnetListener() {
        tailnetListener?.cancel()
        tailnetListener = nil
        tailnetAddress = nil
        publishURLs()
    }

    /// Stops the tunnel process; call when the app quits.
    func shutdown() {
        tunnel.stop()
    }

    /// Mirrors tunnel state into the config file so the URL is discoverable.
    func tunnelStateChanged() {
        publishURLs()
    }

    /// For MCP clients running on this Mac. Tailscale on macOS can't reach this machine's own
    /// tailnet address, so apps here always use loopback.
    var localURL: URL? {
        URL(string: "http://127.0.0.1:\(config.port)/mcp/\(config.token)")
    }

    /// The one URL to hand to any assistant: public when the tunnel is up, loopback until then.
    var shareURL: URL? {
        connectorURL ?? localURL
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
                            // The tunnel must point at the port we actually got.
                            if MCPTunnel.isEnabled {
                                self.tunnel.start(localPort: port)
                            }
                        }
                        self.state = .running(port: port)
                    case let .failed(error), let .waiting(error):
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

    private nonisolated func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private nonisolated func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var data = buffer
            if let chunk {
                data.append(chunk)
            }

            if let request = HTTPRequest(data) {
                // Anything after this request belongs to the next one on a reused connection.
                let leftover = data.count > request.byteCount ? data.subdata(in: request.byteCount ..< data.count) : Data()
                Task { @MainActor in
                    var response = self.respond(to: request)
                    response.keepAlive = request.wantsKeepAlive
                    connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                        if request.wantsKeepAlive {
                            self.receive(on: connection, buffer: leftover)
                        } else {
                            connection.cancel()
                        }
                    })
                }
            } else if isComplete || error != nil || data.count > 4 << 20 {
                connection.cancel()
            } else {
                receive(on: connection, buffer: data)
            }
        }
    }

    private func respond(to request: HTTPRequest) -> HTTPResponse {
        // Requests relayed by the Cloudflare tunnel carry this header; browsers on this Mac can't forge it
        // without a CORS preflight we never answer.
        let viaTunnel = request.headers["cf-connecting-ip"] != nil
        // Browsers send Origin; only allow local pages so a website can't drive the user's planner.
        if !viaTunnel, let origin = request.headers["origin"],
           !(origin.hasPrefix("http://localhost") || origin.hasPrefix("http://127.0.0.1"))
        {
            return HTTPResponse(status: 403, body: Data("Forbidden origin".utf8))
        }
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        let authorized: Bool
        switch path {
        case "/mcp":
            authorized = request.headers["authorization"] == "Bearer \(config.token)"
        case "/mcp/\(config.token)":
            // Token in the path, for connectors that can't send headers (claude.ai, ChatGPT).
            authorized = true
        default:
            return HTTPResponse(status: 404, body: Data("Not found".utf8))
        }
        guard authorized else {
            return HTTPResponse(status: 401, body: Data("Missing or invalid token. Copy the config from Black Hole Settings.".utf8))
        }
        guard !viaTunnel || tunnel.isActive else {
            return HTTPResponse(status: 403, body: Data("Remote access is off in Black Hole Settings.".utf8))
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
    /// Bytes this request occupies, so a pipelined follow-up isn't lost.
    let byteCount: Int

    /// HTTP/1.1 keeps connections open unless the client says otherwise.
    var wantsKeepAlive: Bool {
        headers["connection"]?.lowercased() != "close"
    }

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
        body = data.subdata(in: bodyStart ..< (bodyStart + length))
        byteCount = bodyStart + length
    }
}

struct HTTPResponse {
    var status: Int
    var contentType = "text/plain; charset=utf-8"
    var headers: [String: String] = [:]
    var body: Data
    var keepAlive = false

    func serialized() -> Data {
        let reason = [
            200: "OK",
            202: "Accepted",
            401: "Unauthorized",
            403: "Forbidden",
            404: "Not Found",
            405: "Method Not Allowed"
        ][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n"
        for (key, value) in headers {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}
