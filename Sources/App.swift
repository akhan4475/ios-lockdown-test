import SwiftUI
import Network

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

    var body: some View {
        NavigationView {
            Form {
                Section("Target") {
                    TextField("Host", text: $host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    Button(running ? "Probing..." : "Probe TCP connection") { probe() }
                        .disabled(running)
                }
                Section("Result") {
                    Text(log)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Lockdown Test")
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
