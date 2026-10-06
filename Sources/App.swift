import SwiftUI
import Network
import UniformTypeIdentifiers
import Minimuxer

@main
struct LockdownTestApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var host = "10.7.1.1"
    @State private var port = "62078"
    @State private var log = "Idle."
    @State private var running = false

    @State private var pairingText: String?
    @State private var pairingName = "none loaded"
    @State private var showImporter = false
    @State private var useRP = true
    @State private var overridePeer = ""
    @State private var mmLog = "Idle."
    @State private var mmRunning = false

    var body: some View {
        NavigationView {
            Form {
                Section("TCP probe") {
                    TextField("Host", text: $host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    Button(running ? "Probing..." : "Probe TCP connection") { probe() }
                        .disabled(running)
                    Text(log)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
                Section("Minimuxer (LocalDevVPN must be connected)") {
                    Button("Choose pairing file") { showImporter = true }
                    Text("Pairing file: \(pairingName)").font(.footnote)
                    Toggle("RPPairing file (iOS 17+)", isOn: $useRP)
                    TextField("Override tunnel peer IP (optional)", text: $overridePeer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button(mmRunning ? "Working..." : "Start + fetch UDID") {
                        Task { await runMinimuxer() }
                    }
                    .disabled(mmRunning || pairingText == nil)
                    Text(mmLog)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Lockdown Test")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
                loadPairingFile(result)
            }
        }
    }

    private func loadPairingFile(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            mmLog = "File pick failed: \(e.localizedDescription)"
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                pairingText = try String(contentsOf: url, encoding: .utf8)
                pairingName = url.lastPathComponent
                mmLog = "Pairing file loaded in memory only."
            } catch {
                mmLog = "Could not read file: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func runMinimuxer() async {
        guard let text = pairingText else { return }
        mmRunning = true
        defer { mmRunning = false }

        let peer = overridePeer.trimmingCharacters(in: .whitespaces)
        let rp = useRP
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        let core = Minimuxer.shared.core

        let binding = ConnectionConfigBinding(
            setTunnelIfaceIp: { _ in },
            setTunnelPeerIp: { _ in },
            setTunnelPeerSubnetMask: { _ in },
            setTunnelPeerReachable: { _ in },
            setTunnelIfaceSubnetMask: { _ in },
            getRemoteServerIp: { "" },
            setRemoteReachable: { _ in },
            getOverrideTunnelPeerIp: { peer },
            setOverrideTunnelPeerReachable: { _ in },
            getConnectionMode: { .localVPN }
        )

        mmLog = "Binding connection config..."
        await core.bindConnectionConfig(binding)

        mmLog = "Starting (\(rp ? "rppairing" : "lockdown"))..."
        do {
            try await core.start(pairingFile: text, mountPath: docs, preferred: rp ? .rppairing : .lockdown)
        } catch {
            mmLog = "start() failed: \(error)"
            return
        }

        let ready = await core.isReady(withNetworkCheck: true, withDDIMountCheck: false)
        var out = "isReady: "
        switch ready {
        case .success(let ok): out += "\(ok)"
        case .failure(let err): out += "FAILED - \(core.describeError(err))"
        }

        do {
            let udid = try await core.fetchUDID()
            out += "\nUDID fetched OK (\(udid.count) chars)"
        } catch {
            out += "\nfetchUDID failed: \(error)"
        }
        mmLog = out
    }

    private func probe() {
        let h = host
        let ps = port
        guard let p = NWEndpoint.Port(ps) else {
            log = "Invalid port"
            return
        }
        running = true
        log = "Connecting to \(h):\(ps)..."

        let conn = NWConnection(host: NWEndpoint.Host(h), port: p, using: .tcp)
        var finished = false
        let finish: (String) -> Void = { msg in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                conn.cancel()
                log = msg
                running = false
            }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready: finish("TCP connect OK to \(h):\(ps)")
            case .failed(let e): finish("Failed: \(e)")
            case .waiting(let e): finish("Waiting/unreachable: \(e)")
            default: break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish("Timed out after 5s") }
    }
}
