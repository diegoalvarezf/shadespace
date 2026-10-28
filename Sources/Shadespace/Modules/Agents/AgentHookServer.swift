import Foundation
import Network

/// Minimal HTTP/1.1 server for Claude Code "http" hooks. It binds to 127.0.0.1 only, accepts a
/// single POST path, and checks a per-install token header, so nothing is reachable from the
/// network and stray local requests are ignored. One request per connection.
final class AgentHookServer: @unchecked Sendable {
    static let port: UInt16 = 47823
    static let path = "/claude-code"
    static let tokenHeader = "x-shadespace-token"
    static var url: String { "http://127.0.0.1:\(port)\(path)" }

    /// Hook payloads larger than this are rejected (Write tool inputs can be big, but not this big).
    private static let maxBodySize = 8 * 1024 * 1024

    /// Receives the JSON body and returns the response body (nil = empty 200, "no decision").
    typealias Handler = @Sendable (Data) async -> Data?

    private let token: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "shadespace.agent-hooks")
    private var listener: NWListener?

    private(set) var startError: Error?

    init(token: String, handler: @escaping Handler) {
        self.token = token
        self.handler = handler
    }

    func start() {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    NSLog("Shadespace: hook server failed: \(error)")
                    self?.startError = error
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("Shadespace: hook server couldn't start: \(error)")
            startError = error
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        // Defense in depth: only loopback peers, even though the listener is bound to 127.0.0.1
        if case .hostPort(let host, _) = connection.endpoint, !Self.isLoopback(host) {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = HTTPRequest(buffer) {
                self.respond(to: request, on: connection)
            } else if error != nil || isComplete || buffer.count > Self.maxBodySize {
                self.send(status: "400 Bad Request", body: nil, on: connection)
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        guard request.method == "POST", request.path == Self.path else {
            send(status: "404 Not Found", body: nil, on: connection)
            return
        }
        guard request.headers[Self.tokenHeader] == token else {
            send(status: "403 Forbidden", body: nil, on: connection)
            return
        }
        let handler = self.handler
        Task {
            let body = await handler(request.body)
            self.send(status: "200 OK", body: body, on: connection)
        }
    }

    private func send(status: String, body: Data?, on connection: NWConnection) {
        let body = body ?? Data()
        var response = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if !body.isEmpty { response += "Content-Type: application/json\r\n" }
        response += "\r\n"
        var data = Data(response.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func isLoopback(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let address): return address == .loopback
        case .ipv6(let address): return address == .loopback
        case .name(let name, _): return name == "localhost"
        @unknown default:        return false
        }
    }
}

/// Just enough HTTP/1.1 request parsing for hook calls: request line, headers, and a body
/// delimited by Content-Length. Returns nil until the whole request has arrived.
struct HTTPRequest {
    let method: String
    let path: String
    /// Header names lowercased.
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator),
              let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return nil }

        method = String(requestLine[0])
        // Ignore any query string
        path = String(requestLine[1].split(separator: "?", maxSplits: 1).first ?? "")
        self.headers = headers
        body = data.subdata(in: bodyStart..<(bodyStart + length))
    }
}
