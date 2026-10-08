// A discovery-port probe tests a NEW connection, not an existing developer
// session. During a Wi-Fi/cellular handoff it can fail while that session lives.
enum EndpointRetentionPolicy {
    static func shouldRetain(
        localVPN: Bool,
        remotePairing: Bool,
        currentPeer: String?,
        candidatePeers: [String]
    ) -> Bool {
        guard localVPN, remotePairing,
              let currentPeer, !currentPeer.isEmpty else { return false }
        return candidatePeers.contains(currentPeer)
    }
}
