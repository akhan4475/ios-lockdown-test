@main
struct EndpointRetentionTests {
    static func main() {
        // A handoff can refuse a new discovery-port connection while the
        // already-established session continues over the same loopback route.
        precondition(EndpointRetentionPolicy.shouldRetain(
            localVPN: true, remotePairing: true,
            currentPeer: "10.7.0.1", candidatePeers: ["10.7.0.1"]
        ), "Wi-Fi/cellular handoff must not discard the existing endpoint")
        precondition(!EndpointRetentionPolicy.shouldRetain(
            localVPN: true, remotePairing: true,
            currentPeer: "10.7.0.1", candidatePeers: []
        ), "Disconnecting the VPN must not retain a stale endpoint")
        precondition(!EndpointRetentionPolicy.shouldRetain(
            localVPN: true, remotePairing: true,
            currentPeer: "10.7.0.1", candidatePeers: ["10.8.0.1"]
        ), "Replacing the VPN route must allow endpoint rediscovery")
        precondition(!EndpointRetentionPolicy.shouldRetain(
            localVPN: true, remotePairing: true,
            currentPeer: nil, candidatePeers: ["10.7.0.1"]
        ), "First startup must still perform discovery")
        precondition(!EndpointRetentionPolicy.shouldRetain(
            localVPN: false, remotePairing: true,
            currentPeer: "10.7.0.1", candidatePeers: ["10.7.0.1"]
        ), "Remote-server mode must retain its original behavior")
        precondition(!EndpointRetentionPolicy.shouldRetain(
            localVPN: true, remotePairing: false,
            currentPeer: "10.7.0.1", candidatePeers: ["10.7.0.1"]
        ), "Legacy lockdown mode must retain its original behavior")
        print("Endpoint retention: all six regression checks passed")
    }
}
