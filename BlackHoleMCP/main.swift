// blackhole-mcp: stdio ⇄ HTTP bridge for MCP clients that only launch local commands (e.g. Claude Desktop).
// Reads newline-delimited JSON-RPC from stdin, forwards each message to the running Black Hole app's
// local MCP endpoint, and writes replies to stdout. Logs go to stderr.
import Foundation

struct Config: Decodable {
    var enabled: Bool
    var port: UInt16
    var token: String
}

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/Black Hole/mcp.json")

func log(_ message: String) {
    FileHandle.standardError.write(Data("[blackhole-mcp] \(message)\n".utf8))
}

func loadConfig() -> Config? {
    guard let data = try? Data(contentsOf: configURL) else { return nil }
    return try? JSONDecoder().decode(Config.self, from: data)
}

func writeLine(_ data: Data) {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

/// JSON-RPC error for a request we couldn't deliver, so the client shows a useful message.
func deliveryError(for message: Data, _ text: String) -> Data? {
    guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
          let id = object["id"], !(id is NSNull) else { return nil }
    let reply: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": text]]
    return try? JSONSerialization.data(withJSONObject: reply)
}

func launchApp() {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-g", "-b", "app.getblackhole.mac"]
    try? open.run()
    open.waitUntilExit()
}

/// POSTs one message; returns (status, body) or nil if the app isn't reachable.
func post(_ message: Data, config: Config) -> (Int, Data)? {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(config.port)/mcp")!)
    request.httpMethod = "POST"
    request.httpBody = message
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")

    let done = DispatchSemaphore(value: 0)
    var result: (Int, Data)?
    URLSession.shared.dataTask(with: request) { data, response, _ in
        if let http = response as? HTTPURLResponse { result = (http.statusCode, data ?? Data()) }
        done.signal()
    }.resume()
    done.wait()
    return result
}

func forward(_ message: Data) {
    guard var config = loadConfig() else {
        if let reply = deliveryError(for: message, "Black Hole isn't set up for MCP. Open Black Hole → Settings and turn on the MCP server.") { writeLine(reply) }
        return
    }
    guard config.enabled else {
        if let reply = deliveryError(for: message, "The MCP server is off. Turn it on in Black Hole → Settings.") { writeLine(reply) }
        return
    }

    var outcome = post(message, config: config)
    if outcome == nil {
        log("Black Hole isn't responding; launching it")
        launchApp()
        for _ in 0..<20 where outcome == nil {
            Thread.sleep(forTimeInterval: 0.5)
            config = loadConfig() ?? config
            outcome = post(message, config: config)
        }
    }

    guard let (status, body) = outcome else {
        if let reply = deliveryError(for: message, "Couldn't reach Black Hole on port \(config.port). Is the app running with the MCP server on?") { writeLine(reply) }
        return
    }
    switch status {
    case 200 where !body.isEmpty: writeLine(body)
    case 200, 202: break
    default:
        let text = String(data: body, encoding: .utf8) ?? "HTTP \(status)"
        if let reply = deliveryError(for: message, "Black Hole returned \(status): \(text)") { writeLine(reply) }
    }
}

setvbuf(stdout, nil, _IONBF, 0)
while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { continue }
    forward(Data(trimmed.utf8))
}
