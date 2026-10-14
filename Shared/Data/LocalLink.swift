import Combine
import Foundation
import MultipeerConnectivity

final class LocalLink: NSObject, ObservableObject, LocalTransport {
    @Published var peers: [MCPeerID] = []
    @Published var connected = false
    @Published var status = "Offline • misi lokal tetap berjalan"
    @Published var invitationName: String?
    @Published var transferStatus = "Belum ada transfer"
    var onPacket: ((Packet) -> Void)?
    var onConnect: (() -> Void)?
    let store: any DatasetRepository
    var connectionChanges: AnyPublisher<Bool, Never> { $connected.eraseToAnyPublisher() }
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private var invitation: ((Bool, MCSession?) -> Void)?
    private let fileQueue = DispatchQueue(label: "mapping.transfer", qos: .utility)
    @Published private(set) var sending = false
    @Published private(set) var receiving = false
    @Published var receivedMissionID: UUID?
    private let isCamera: Bool
    private let identities: PeerIdentityStore
    private var reconnectPolicy = ReconnectPolicy()
    private var retryTimer: Timer?
    private var attemptingPeer: MCPeerID?
    private var attemptExpiresAt: Double = 0
    private var lastDiscoveryRefresh: Double = 0

    init(camera: Bool, enabled: Bool = true, store: any DatasetRepository = DatasetStore()) {
        self.store = store
        isCamera = camera
        let identities = PeerIdentityStore(camera: camera)
        self.identities = identities
        let peer = identities.localPeer()
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(
            peer: peer, discoveryInfo: ["role": camera ? "camera" : "control"], serviceType: "drone-map")
        browser = MCNearbyServiceBrowser(peer: peer, serviceType: "drone-map")
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        guard enabled else { return }
        if camera { advertiser.startAdvertisingPeer() } else { browser.startBrowsingForPeers() }
        lastDiscoveryRefresh = ProcessInfo.processInfo.systemUptime
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.maintainConnection()
        }
    }
    deinit { retryTimer?.invalidate() }
    private func maintainConnection() {
        guard !connected else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if attemptingPeer != nil {
            guard now >= attemptExpiresAt else { return }
            attemptingPeer = nil
        }
        // Keep discovery alive after radio loss without changing capture state.
        if now - lastDiscoveryRefresh >= 20 {
            lastDiscoveryRefresh = now
            if isCamera {
                advertiser.stopAdvertisingPeer()
                advertiser.startAdvertisingPeer()
            } else {
                peers.removeAll()
                browser.stopBrowsingForPeers()
                browser.startBrowsingForPeers()
            }
        }
        guard !isCamera, let approved = identities.approvedPeer else { return }
        status = "Mencari iPhone yang dipasangkan • reconnect otomatis"
        guard reconnectPolicy.canAttempt(now: now), let peer = peers.first(where: { $0 == approved }) else {
            return
        }
        invite(peer, automatic: true)
    }
    private func invite(_ peer: MCPeerID, automatic: Bool) {
        guard !connected, attemptingPeer == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        attemptingPeer = peer
        attemptExpiresAt = now + reconnectPolicy.invitationTimeout
        reconnectPolicy.didAttempt(now: now)
        status = automatic ? "Menghubungkan kembali ke iPhone…" : "Menunggu persetujuan di iPhone…"
        browser.invitePeer(peer, to: session, withContext: nil, timeout: reconnectPolicy.invitationTimeout)
    }
    func connect(_ peer: MCPeerID) {
        invite(peer, automatic: identities.approvedPeer == peer)
    }
    func answerInvitation(_ accept: Bool) {
        invitation?(accept, accept ? session : nil)
        invitation = nil
        invitationName = nil
    }
    func send(_ packet: Packet) throws {
        guard !session.connectedPeers.isEmpty else { throw MappingError.invalid("Perangkat tidak terhubung") }
        let data = try JSONEncoder().encode(packet)
        guard data.count < 1_048_576 else { throw MappingError.invalid("Pesan terlalu besar") }
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
    func export(_ id: UUID) throws {
        guard !sending, let peer = session.connectedPeers.first else {
            throw MappingError.invalid("Transfer sibuk atau koneksi terputus")
        }
        sending = true
        transferStatus = "Menyiapkan dataset…"
        fileQueue.async {
            do {
                try self.store.migrateLegacy()
                let files = try self.store.files(id)
                self.sendNext(files, index: 0, mission: id, peer: peer)
            } catch { self.finishTransfer(error.localizedDescription) }
        }
    }
    private func sendNext(_ files: [URL], index: Int, mission: UUID, peer: MCPeerID) {
        guard index < files.count else {
            finishTransfer("Transfer selesai: \(files.count) berkas dikirim")
            return
        }
        do {
            let file = files[index]
            let hash = try DatasetStore.hashFile(file)
            let relative = String(file.path.dropFirst(store.directory(mission).path.count + 1))
            let name =
                "\(mission.uuidString)|\(hash)|\(relative)|\(store.directory(mission).lastPathComponent)"
            DispatchQueue.main.async { self.transferStatus = "Mengirim \(index + 1)/\(files.count)" }
            session.sendResource(at: file, withName: name, toPeer: peer) { error in
                self.fileQueue.async {
                    if let error {
                        self.finishTransfer(error.localizedDescription)
                    } else {
                        self.sendNext(files, index: index + 1, mission: mission, peer: peer)
                    }
                }
            }
        } catch { finishTransfer(error.localizedDescription) }
    }
    private func finishTransfer(_ message: String) {
        DispatchQueue.main.async {
            self.sending = false
            self.transferStatus = message
        }
    }
}

extension LocalLink: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        DispatchQueue.main.async {
            guard self.session.connectedPeers.isEmpty else {
                invitationHandler(false, nil)
                return
            }
            if self.identities.approvedPeer == peerID {
                // A previously approved ground station may reconnect while the phone is airborne.
                self.answerInvitation(false)
                invitationHandler(true, self.session)
                return
            }
            guard self.invitation == nil else {
                invitationHandler(false, nil)
                return
            }
            self.invitation = invitationHandler
            self.invitationName = peerID.displayName
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { self.status = error.localizedDescription }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { self.status = error.localizedDescription }
    }
    func browser(
        _ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard info?["role"] == "camera" else { return }
        DispatchQueue.main.async {
            if !self.peers.contains(peerID) { self.peers.append(peerID) }
            self.maintainConnection()
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.peers.removeAll { $0 == peerID } }
    }
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connected = !session.connectedPeers.isEmpty
            switch state {
            case .connected:
                self.identities.approve(peerID)
                self.attemptingPeer = nil
                self.reconnectPolicy.didConnect()
                self.status = "Terhubung • \(peerID.displayName)"
                self.onConnect?()
            case .connecting:
                self.attemptingPeer = peerID
                self.attemptExpiresAt =
                    ProcessInfo.processInfo.systemUptime + self.reconnectPolicy.invitationTimeout
                self.status = "Menghubungkan • \(peerID.displayName)"
            case .notConnected:
                if self.attemptingPeer == peerID { self.attemptingPeer = nil }
                if !self.connected {
                    self.receiving = false
                    self.status =
                        self.isCamera
                        ? "Mac terputus • menunggu reconnect otomatis" : "Mencari iPhone • reconnect otomatis"
                    self.maintainConnection()
                }
            @unknown default: break
            }
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count < 1_048_576, let packet = try? JSONDecoder().decode(Packet.self, from: data),
            packet.version == 1
        else { return }
        DispatchQueue.main.async { self.onPacket?(packet) }
    }
    func session(
        _ session: MCSession, didReceive stream: InputStream, withName streamName: String,
        fromPeer peerID: MCPeerID
    ) { stream.close() }
    func session(
        _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, with progress: Progress
    ) {
        DispatchQueue.main.async {
            self.receiving = true
            self.transferStatus = "Menerima dataset…"
        }
    }
    func session(
        _ session: MCSession, didFinishReceivingResourceWithName name: String, fromPeer peerID: MCPeerID,
        at localURL: URL?, withError error: Error?
    ) {
        guard !isCamera else { return }
        // MCSession removes its temporary URL after this delegate returns: copy first.
        do {
            if let error { throw error }
            guard let localURL else { throw MappingError.invalid("Berkas transfer hilang") }
            let (destination, expectedHash) = try DatasetStore.destination(resource: name, root: store.root)
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: localURL, to: staging)
            fileQueue.async {
                defer { try? FileManager.default.removeItem(at: staging) }
                do {
                    guard try DatasetStore.hashFile(staging) == expectedHash else {
                        throw MappingError.invalid("Checksum tidak cocok; unduh ulang")
                    }
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
                    } else {
                        try FileManager.default.moveItem(at: staging, to: destination)
                    }
                    if destination.lastPathComponent == "mission.json",
                        let id = UUID(uuidString: name.components(separatedBy: "|")[0])
                    {
                        try self.store.verify(id)
                        DispatchQueue.main.async {
                            self.receiving = false
                            self.receivedMissionID = id
                            self.transferStatus = "Transfer selesai • dataset terverifikasi"
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.transferStatus = "Menerima • \(destination.lastPathComponent) terverifikasi"
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.receiving = false
                        self.transferStatus = error.localizedDescription
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.receiving = false
                self.transferStatus = error.localizedDescription
            }
        }
    }
}
