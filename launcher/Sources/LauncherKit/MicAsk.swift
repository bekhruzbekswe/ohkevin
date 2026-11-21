import Foundation
import Network

/// Asks the call's Chrome for the microphone before any call: a tiny page served on 127.0.0.1 (the call's own address, so Chrome
/// remembers the answer for every call) that asks once, stops the track at once, and says what happened. The launcher never uses the
/// microphone itself, and the page makes no sound. It listens only while it is asking.
final class MicAsk: @unchecked Sendable {
    enum Answer: String { case ok, chrome, mac }

    let port: Int
    let token = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    private let listener: NWListener
    private let answered: @Sendable (Answer) -> Void

    var url: URL { URL(string: "http://127.0.0.1:\(port)/?k=\(token)")! }

    /// Nil when the port cannot be listened on (a call has it).
    init?(port: Int, answered: @escaping @Sendable (Answer) -> Void) {
        let parameters = NWParameters.tcp
        guard let number = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: number) // this Mac only
        guard let listener = try? NWListener(using: parameters) else { return nil }
        self.port = port; self.listener = listener; self.answered = answered
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
    }

    func start() { listener.start(queue: .global()) }
    func stop() { listener.cancel() }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let head = String(data: data, encoding: .utf8)?.split(separator: "\r\n").first else { return connection.cancel() }
            let words = head.split(separator: " ")
            let target = words.count > 1 ? String(words[1]) : ""
            var body = "", type = "text/plain", status = "200 OK"
            if target.contains("k=\(self.token)") {
                if words[0] == "GET", target.hasPrefix("/?") { body = Self.page; type = "text/html; charset=utf-8" }
                else if words[0] == "POST", target.hasPrefix("/mic/"), let answer = Answer(rawValue: String(target.dropFirst(5).prefix { $0 != "?" })) { self.answered(answer) }
                else { status = "404 Not Found" }
            } else { status = "403 Forbidden" }
            let reply = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// The page: it asks, lets go of the microphone at once, and posts ok, chrome (Chrome's own no) or mac (the system's no, as the
    /// call page reads it).
    static let page = """
    <!doctype html><meta charset="utf-8"><title>Oh Kevin</title>
    <body style="font:17px -apple-system,system-ui;background:#F6F3EC;color:#57534B;margin:40px">Allow the microphone for Oh Kevin.
    <script>
    const k = new URLSearchParams(location.search).get('k')
    const say = r => fetch('/mic/' + r + '?k=' + k, { method: 'POST' }).catch(() => {})
    navigator.mediaDevices.getUserMedia({ audio: true }).then(s => { s.getTracks().forEach(t => t.stop()); say('ok') }, async e => {
      const site = await navigator.permissions?.query({ name: 'microphone' }).catch(() => null)
      say(/system/i.test(e.message) || site?.state === 'granted' ? 'mac' : 'chrome')
    })
    </script>
    """
}
