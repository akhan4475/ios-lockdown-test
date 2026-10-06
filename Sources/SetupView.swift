import SwiftUI

struct SetupView: View {
    @EnvironmentObject var engine: LocationEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Text(engine.status).font(.footnote)
                    Button(engine.busy ? "Working..." : "Reconnect") {
                        Task { await engine.bootstrap() }
                    }
                    .disabled(engine.busy)
                    Text("LocalDevVPN must be connected before you reconnect.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Pairing file") {
                    Text(engine.pairingName.map { "Saved in app: \($0)" } ?? "No pairing file in the app.")
                        .font(.footnote)
                    Button("Choose pairing file...") { showImporter = true }
                    if engine.pairingName != nil {
                        Button("Delete pairing file from app", role: .destructive) {
                            engine.deletePairingFile()
                        }
                    }
                    Text("The file stays inside the app and is excluded from backups.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Developer image") {
                    Text(engine.ddiMounted.map { $0 ? "Mounted" : "Not mounted" } ?? "Unknown (connect first)")
                        .font(.footnote)
                    Button("Mount developer image (downloads ~12 MB)") {
                        Task { await engine.mountDDI() }
                    }
                    .disabled(!engine.isReady || engine.busy)
                    Text("Needed again after each phone restart.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Options") {
                    Toggle("Keep alive in background (silent audio)", isOn: $engine.keepAlive)
                    TextField("Override tunnel peer IP (optional)", text: $engine.overridePeer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if !engine.message.isEmpty {
                    Section("Last message") { Text(engine.message).font(.footnote) }
                }
            }
            .navigationTitle("Setup")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
                if case .success(let url) = result {
                    engine.importPairingFile(from: url)
                    Task { await engine.bootstrap() }
                }
            }
        }
    }
}
