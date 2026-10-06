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
    @State private var ddiLog = "Not checked."
    @State private var ddiRunning = false
    @State private var latText = "40.7580"
    @State private var lonText = "-73.9855"
    @State private var locLog = "Idle."
    @State private var locRunning = false
    @State private var keepAlive = true
    @State private var holdTask: Task<Void, Never>?

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
                Section("Developer disk image (run Start first)") {
                    Button("Check if mounted") { Task { await checkDDI() } }
                        .disabled(ddiRunning)
                    Button(ddiRunning ? "Working..." : "Mount (downloads ~18 MB)") {
                        Task { await mountDDI() }
                    }
                    .disabled(ddiRunning)
                    Text(ddiLog)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
                Section("Location test (run Start, then mount the DDI first)") {
                    TextField("Latitude", text: $latText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Longitude", text: $lonText)
                        .keyboardType(.numbersAndPunctuation)
                    Toggle("Keep alive in background (silent audio)", isOn: $keepAlive)
                    Button(locRunning ? "Working..." : "Set + hold location") {
                        Task { await setLocation() }
                    }
                    .disabled(locRunning)
                    Button("Clear location (back to real GPS)") {
                        Task { await clearLocation() }
                    }
                    .disabled(locRunning)
                    Text(locLog)
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

    @MainActor
    private func setLocation() async {
        guard let lat = Double(latText.trimmingCharacters(in: .whitespaces)),
              let lon = Double(lonText.trimmingCharacters(in: .whitespaces)),
              (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon) else {
            locLog = "Enter a valid latitude (-90 to 90) and longitude (-180 to 180)."
            return
        }
        locRunning = true
        defer { locRunning = false }
        await stopHolding()
        locLog = "Setting \(lat), \(lon)..."
        do {
            try await Minimuxer.shared.core.setSimulatedLocation(latitude: lat, longitude: lon)
        } catch {
            locLog = "Set failed: \(error)"
            return
        }
        startHolding(lat: lat, lon: lon)
    }

    @MainActor
    private func startHolding(lat: Double, lon: Double) {
        if keepAlive { KeepAlive.shared.start() }
        let start = Date()
        holdTask = Task { @MainActor in
            var ok = 0
            var failed = 0
            var lastError = ""
            while !Task.isCancelled {
                do {
                    try await Minimuxer.shared.core.setSimulatedLocation(latitude: lat, longitude: lon)
                    ok += 1
                } catch {
                    failed += 1
                    lastError = "\(error)"
                }
                let secs = Int(Date().timeIntervalSince(start))
                locLog = "Holding \(lat), \(lon)\nrunning \(secs)s  ok: \(ok)  failed: \(failed)"
                    + (lastError.isEmpty ? "" : "\nlast error: \(lastError)")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    @MainActor
    private func stopHolding() async {
        holdTask?.cancel()
        await holdTask?.value
        holdTask = nil
        KeepAlive.shared.stop()
    }

    @MainActor
    private func clearLocation() async {
        locRunning = true
        defer { locRunning = false }
        await stopHolding()
        do {
            try await Minimuxer.shared.core.clearSimulatedLocation()
            locLog = "Cleared. Real GPS restored."
        } catch {
            locLog = "Clear failed: \(error)"
        }
    }

    @MainActor
    private func checkDDI() async {
        ddiRunning = true
        defer { ddiRunning = false }
        do {
            let mounted = try await Minimuxer.shared.core.isDDIMounted()
            ddiLog = "DDI mounted: \(mounted)"
        } catch {
            ddiLog = "Check failed: \(error)"
        }
    }

    @MainActor
    private func mountDDI() async {
        ddiRunning = true
        defer { ddiRunning = false }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        ddiLog = "Mounting (may take a minute)..."
        do {
            let didMount = try await Minimuxer.shared.core.mountDDI(docsPath: docs)
            ddiLog = didMount ? "Mounted now." : "Was already mounted."
        } catch {
            ddiLog = "Mount failed: \(error)"
        }
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
