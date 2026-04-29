import AppKit
import Combine
import Foundation
import Network

extension Notification.Name {
    /// Disparada quando configurações de sincronização mudam (toggle, token, etc.).
    static let clipoSyncSettingsChanged = Notification.Name("clipoSyncSettingsChanged")
}

// MARK: - Modelos

/// Peer descoberto na tailnet.
struct TailscalePeer: Hashable {
    let id: String
    let name: String
    let ip: String
    let online: Bool
    let os: String

    var endpoint: URL? {
        URL(string: "http://\(ip):\(Preferences.shared.syncPort)")
    }
}

/// Payload trocado entre dispositivos.
struct SyncMessage: Codable {
    let originId: String
    let originName: String
    let kind: String   // "text" | "link" | "image" | "file"
    let text: String?
    let imageBase64: String?
    let timestamp: TimeInterval
}

// MARK: - Detector / discovery

/// Localiza o CLI do Tailscale e lista os peers da tailnet.
enum TailscaleDetector {

    /// Caminhos possíveis do binário `tailscale`.
    private static let candidates = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/bin/tailscale",
        "/opt/local/bin/tailscale"
    ]

    /// Retorna o caminho do binário, se encontrado.
    static func binaryPath() -> String? {
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// Executa `tailscale status --json` e devolve `(self, peers)`.
    static func status() -> (selfPeer: TailscalePeer?, peers: [TailscalePeer]) {
        guard let bin = binaryPath() else { return (nil, []) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["status", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return (nil, [])
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, [])
        }

        let selfPeer = parsePeer(json["Self"] as? [String: Any], idKey: "ID")
        var peers: [TailscalePeer] = []
        if let peerMap = json["Peer"] as? [String: [String: Any]] {
            for (key, value) in peerMap {
                if let p = parsePeer(value, idKey: key) {
                    peers.append(p)
                }
            }
        }
        peers.sort { $0.name < $1.name }
        return (selfPeer, peers)
    }

    private static func parsePeer(_ dict: [String: Any]?, idKey: String) -> TailscalePeer? {
        guard let dict = dict else { return nil }
        let ips = dict["TailscaleIPs"] as? [String] ?? []
        guard let ip = ips.first(where: { $0.hasPrefix("100.") }) ?? ips.first else {
            return nil
        }
        let id = (dict["ID"] as? String) ?? idKey
        let host = (dict["HostName"] as? String) ?? (dict["DNSName"] as? String) ?? ip
        let online = (dict["Online"] as? Bool) ?? false
        let os = (dict["OS"] as? String) ?? ""
        return TailscalePeer(id: id, name: host, ip: ip, online: online, os: os)
    }
}

// MARK: - Servidor HTTP

/// Servidor TCP minimalista que entende um POST /clip e GET /ping.
/// Aceita apenas conexões vindas do range Tailscale (100.64.0.0/10).
final class SyncServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "clipo.sync.server")
    private let onMessage: (SyncMessage) -> Void

    init(onMessage: @escaping (SyncMessage) -> Void) {
        self.onMessage = onMessage
    }

    func start() {
        stop()
        let prefs = Preferences.shared
        guard let port = NWEndpoint.Port(rawValue: prefs.syncPort) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    NSLog("Clipo sync: listener falhou — \(err)")
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("Clipo sync: não foi possível abrir porta \(prefs.syncPort) — \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Connection handling

    private func handle(_ conn: NWConnection) {
        if !isAcceptableRemote(conn) {
            conn.cancel()
            return
        }
        conn.start(queue: queue)
        readRequest(conn, buffer: Data())
    }

    private func isAcceptableRemote(_ conn: NWConnection) -> Bool {
        guard case let .hostPort(host, _) = conn.endpoint else { return false }
        let ip: String
        switch host {
        case .ipv4(let addr):
            ip = "\(addr)"
        case .ipv6(let addr):
            ip = "\(addr)"
        default:
            return false
        }
        // Loopback (testes locais) ou range Tailscale CGNAT 100.64.0.0/10.
        if ip.hasPrefix("127.") || ip == "::1" { return true }
        if ip.hasPrefix("100.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (64...127).contains(second) {
                return true
            }
        }
        return false
    }

    private func readRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                NSLog("Clipo sync: erro de leitura — \(error)")
                conn.cancel()
                return
            }
            var current = buffer
            if let data = data { current.append(data) }

            if let (head, body, total) = Self.tryParseHTTP(current) {
                if current.count >= total {
                    self.respond(conn, head: head, body: body)
                    return
                }
            }
            if isComplete {
                conn.cancel()
                return
            }
            if current.count > 16 * 1024 * 1024 { // 16 MB hard limit
                self.send(conn, status: "413 Payload Too Large", body: Data())
                return
            }
            self.readRequest(conn, buffer: current)
        }
    }

    /// Tenta parsear cabeçalho + corpo. Retorna `(head, body, totalEsperado)` quando o cabeçalho está completo.
    private static func tryParseHTTP(_ data: Data) -> (head: HTTPHead, body: Data, total: Int)? {
        let separator = Data([0x0d, 0x0a, 0x0d, 0x0a]) // \r\n\r\n
        guard let range = data.range(of: separator) else { return nil }
        let headData = data.subdata(in: 0..<range.lowerBound)
        guard let headStr = String(data: headData, encoding: .utf8) else { return nil }
        let lines = headStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let idx = line.firstIndex(of: ":") {
                let key = line[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let bodyStart = range.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let total = bodyStart + contentLength
        let bodyEnd = min(data.count, total)
        let body = data.subdata(in: bodyStart..<bodyEnd)
        return (HTTPHead(method: method, path: path, headers: headers), body, total)
    }

    private struct HTTPHead {
        let method: String
        let path: String
        let headers: [String: String]
    }

    private func respond(_ conn: NWConnection, head: HTTPHead, body: Data) {
        let prefs = Preferences.shared

        switch (head.method, head.path) {
        case ("GET", "/ping"):
            let payload: [String: Any] = [
                "ok": true,
                "device": prefs.deviceName,
                "deviceId": prefs.deviceId
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            send(conn, status: "200 OK", body: data, contentType: "application/json")

        case ("POST", "/clip"):
            do {
                let msg = try JSONDecoder().decode(SyncMessage.self, from: body)
                if msg.originId != prefs.deviceId {
                    DispatchQueue.main.async { [weak self] in
                        self?.onMessage(msg)
                    }
                }
                send(conn, status: "200 OK", body: Data("{\"ok\":true}".utf8), contentType: "application/json")
            } catch {
                send(conn, status: "400 Bad Request", body: Data("invalid json".utf8))
            }

        default:
            send(conn, status: "404 Not Found", body: Data())
        }
    }

    private func send(_ conn: NWConnection, status: String, body: Data, contentType: String = "text/plain") {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}

// MARK: - Cliente

/// Faz POST de mensagens para todos os peers.
enum SyncClient {

    static func broadcast(_ message: SyncMessage, to peers: [TailscalePeer]) {
        guard !peers.isEmpty else { return }
        guard let body = try? JSONEncoder().encode(message) else { return }

        let session = sharedSession
        for peer in peers where peer.online {
            guard let url = peer.endpoint?.appendingPathComponent("clip") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            req.timeoutInterval = 5

            let task = session.dataTask(with: req) { _, response, error in
                if let error = error {
                    NSLog("Clipo sync: falha enviando para \(peer.name) — \(error.localizedDescription)")
                } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    NSLog("Clipo sync: \(peer.name) respondeu \(http.statusCode)")
                }
            }
            task.resume()
        }
    }

    private static let sharedSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 10
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()
}

// MARK: - Manager

/// Orquestra descoberta de peers, servidor e envio.
@MainActor
final class TailscaleSyncManager {
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private var server: SyncServer?
    private var refreshTimer: Timer?

    /// Limite (em bytes) para imagens enviadas, evita travar a rede.
    private let imageSizeLimit = 8 * 1024 * 1024

    /// Peers conhecidos no momento.
    private(set) var peers: [TailscalePeer] = []
    private(set) var lastError: String?

    /// Notificado quando a lista de peers muda (para a UI).
    var onPeersChanged: (() -> Void)?

    init(store: HistoryStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    func start() {
        stop()
        guard Preferences.shared.syncEnabled else { return }
        guard TailscaleDetector.binaryPath() != nil else {
            lastError = "Tailscale não encontrado"
            onPeersChanged?()
            return
        }
        lastError = nil

        let server = SyncServer(onMessage: { [weak self] msg in
            self?.handleIncoming(msg)
        })
        server.start()
        self.server = server

        refreshPeers()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPeers() }
        }

        store.outgoingHandler = { [weak self] item in
            self?.broadcast(item: item)
        }
    }

    func stop() {
        server?.stop()
        server = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        store.outgoingHandler = nil
    }

    func refreshPeers() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = TailscaleDetector.status()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.peers = result.peers
                self.onPeersChanged?()
            }
        }
    }

    // MARK: Outgoing

    private func broadcast(item: ClipItem) {
        guard Preferences.shared.syncEnabled else { return }
        guard let message = encode(item: item) else { return }
        let targets = peers.filter { $0.online }
        guard !targets.isEmpty else { return }
        SyncClient.broadcast(message, to: targets)
    }

    private func encode(item: ClipItem) -> SyncMessage? {
        let prefs = Preferences.shared
        switch item.kind {
        case .text, .link:
            guard let text = item.text else { return nil }
            return SyncMessage(
                originId: prefs.deviceId,
                originName: prefs.deviceName,
                kind: item.kind.rawValue,
                text: text,
                imageBase64: nil,
                timestamp: item.createdAt.timeIntervalSince1970
            )

        case .image:
            guard prefs.syncIncludeImages, let path = item.imagePath else { return nil }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  data.count <= imageSizeLimit else { return nil }
            return SyncMessage(
                originId: prefs.deviceId,
                originName: prefs.deviceName,
                kind: "image",
                text: nil,
                imageBase64: data.base64EncodedString(),
                timestamp: item.createdAt.timeIntervalSince1970
            )

        case .file:
            // Caminhos de arquivo não fazem sentido entre máquinas — não envia.
            return nil
        }
    }

    // MARK: Incoming

    private func handleIncoming(_ msg: SyncMessage) {
        switch msg.kind {
        case "text", "link":
            guard let text = msg.text, !text.isEmpty else { return }
            store.addRemoteText(text)
        case "image":
            guard Preferences.shared.syncIncludeImages,
                  let b64 = msg.imageBase64,
                  let data = Data(base64Encoded: b64),
                  let image = NSImage(data: data) else { return }
            store.addRemoteImage(image)
        default:
            break
        }
    }
}

// MARK: - Coordinator (ponte para a UI)

/// Singleton observável que a SettingsView usa para mostrar peers e estado.
@MainActor
final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    @Published private(set) var peers: [TailscalePeer] = []
    @Published private(set) var tailscaleAvailable: Bool = TailscaleDetector.binaryPath() != nil

    private weak var manager: TailscaleSyncManager?

    private init() {}

    func bind(_ manager: TailscaleSyncManager) {
        self.manager = manager
        manager.onPeersChanged = { [weak self] in
            guard let self = self else { return }
            self.peers = manager.peers
            self.tailscaleAvailable = TailscaleDetector.binaryPath() != nil
        }
    }

    func refresh() {
        tailscaleAvailable = TailscaleDetector.binaryPath() != nil
        manager?.refreshPeers()
    }
}
