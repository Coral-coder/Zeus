import Foundation
import Network
import Security

/// A minimal HTTPS server bound to the loopback interface, hosting the OTA
/// endpoints iOS's install daemon fetches. Native equivalent of the LOCAL_MODE
/// HTTPS server in `ipa_sideload`'s `src/server.js`.
///
/// Only serves small, well-known GET routes; the router closure (owned by
/// `SideloadModel`) resolves each one. Loopback-only + per-install tokens keep
/// it off the LAN and gated.
final class LoopbackServer {
    let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.lightwave.zeus.sideload.server")
    private let router: (_ method: String, _ path: String, _ query: [String: String]) -> HTTPResponse

    private(set) var isRunning = false

    init(port: UInt16, router: @escaping (_ method: String, _ path: String, _ query: [String: String]) -> HTTPResponse) {
        self.port = port
        self.router = router
    }

    /// Base URL the OTA links point at (loopback; matches the cert's SAN).
    var baseURL: String { "https://127.0.0.1:\(port)" }

    func start(identity: SecIdentity) throws {
        guard listener == nil else { return }
        let sec = try LoopbackIdentity.secIdentity(from: identity)
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, sec)

        let params = NWParameters(tls: tls)
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.isRunning = true
            case .failed, .cancelled: self?.isRunning = false
            default: break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = Self.headerEnd(in: buf) {
                self.respond(conn, head: buf.subdata(in: buf.startIndex..<end))
                return
            }
            if isComplete || error != nil || buf.count > 1_000_000 { conn.cancel(); return }
            self.receive(conn, buffer: buf)
        }
    }

    private func respond(_ conn: NWConnection, head: Data) {
        let text = String(decoding: head, as: UTF8.self)
        let firstLine = text.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = firstLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let target = parts.count > 1 ? String(parts[1]) : "/"
        let (path, query) = Self.parseTarget(target)
        send(conn, router(method, path, query))
    }

    private func send(_ conn: NWConnection, _ response: HTTPResponse) {
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        var headText = "HTTP/1.1 \(response.status) \(response.statusText)\r\n"
        for (k, v) in headers { headText += "\(k): \(v)\r\n" }
        headText += "\r\n"
        var out = Data(headText.utf8)
        out.append(response.body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Parsing helpers

    private static func headerEnd(in data: Data) -> Int? {
        let sep: [UInt8] = [13, 10, 13, 10] // \r\n\r\n
        guard data.count >= sep.count else { return nil }
        let bytes = [UInt8](data)
        var i = 0
        while i <= bytes.count - sep.count {
            if Array(bytes[i..<i + sep.count]) == sep { return data.startIndex + i + sep.count }
            i += 1
        }
        return nil
    }

    private static func parseTarget(_ target: String) -> (path: String, query: [String: String]) {
        let split = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(split.first ?? "/")
        var query: [String: String] = [:]
        if split.count > 1 {
            for pair in split[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
                query[key] = value
            }
        }
        return (path, query)
    }
}

/// A tiny HTTP response value the router builds for each route.
struct HTTPResponse {
    var status: Int
    var statusText: String
    var headers: [String: String]
    var body: Data

    init(status: Int = 200, statusText: String = "OK", contentType: String, body: Data) {
        self.status = status
        self.statusText = statusText
        self.headers = ["Content-Type": contentType]
        self.body = body
    }

    static func text(_ s: String, contentType: String = "text/plain; charset=utf-8", status: Int = 200, statusText: String = "OK") -> HTTPResponse {
        HTTPResponse(status: status, statusText: statusText, contentType: contentType, body: Data(s.utf8))
    }

    static func notFound() -> HTTPResponse { .text("not found", status: 404, statusText: "Not Found") }
    static func forbidden() -> HTTPResponse { .text("forbidden", status: 403, statusText: "Forbidden") }
    static func gone() -> HTTPResponse { .text("gone", status: 410, statusText: "Gone") }
}
