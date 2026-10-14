import Foundation
import MultipeerConnectivity

// Retain the full MCPeerID, never match an approved device by display name alone.
// This is application pairing continuity, not certificate-based authentication.
final class PeerIdentityStore {
    private let defaults: UserDefaults
    private let prefix: String
    init(camera: Bool, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prefix = camera ? "mapping.camera" : "mapping.control"
    }
    func localPeer() -> MCPeerID {
        if let peer = read("localPeer") { return peer }
        let role = prefix.hasSuffix("camera") ? "DroneCam" : "DroneControl"
        let peer = MCPeerID(displayName: "\(role)-\(UUID().uuidString.prefix(4))")
        save(peer, key: "localPeer")
        return peer
    }
    var approvedPeer: MCPeerID? { read("approvedPeer") }
    func approve(_ peer: MCPeerID) { save(peer, key: "approvedPeer") }
    private func read(_ key: String) -> MCPeerID? {
        guard let data = defaults.data(forKey: "\(prefix).\(key)") else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data)
    }
    private func save(_ peer: MCPeerID, key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: peer, requiringSecureCoding: true)
        else { return }
        defaults.set(data, forKey: "\(prefix).\(key)")
    }
}
