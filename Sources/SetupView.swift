import SwiftUI

struct SetupView: View {
    @EnvironmentObject var engine: LocationEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var showOutsideSetup = false
    @ObservedObject private var alerts = SessionAlerts.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Button("Start without Wi-Fi...") { showOutsideSetup = true }
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

                Section("Connection alerts") {
                    Text(alerts.enabled ? "Connection alerts are enabled." : "Connection alerts are off.")
                    if alerts.enabled {
                        Button("Turn alerts off") { alerts.disable() }
                        Button("Send a test notification in 3 seconds") { alerts.testNotification() }
                    } else {
                        Button("Enable alerts") {
                            Task {
                                await alerts.enable()
                                if engine.holding { alerts.beginSession() }
                            }
                        }
                    }
                    Text(alerts.permissionText).font(.caption).foregroundStyle(.secondary)
                    Text("Alerts warn once when a location command fails, or if successful updates go quiet for about 20–25 seconds. A scheduled warning can still appear if the app stops while the phone is on. Clear location cancels monitoring.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Alerts cannot verify Find My, turn sharing off, or reach a powered-off phone. Focus and notification settings can silence or delay them.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !alerts.schedulingError.isEmpty {
                        Text(alerts.schedulingError).font(.caption).foregroundStyle(.orange)
                    }
                }

                Section("Options") {
                    Toggle("Keep alive in background (silent audio)", isOn: $engine.keepAlive)
                    Text("Helps location updates continue when you lock the phone or switch apps. It uses extra battery and does not keep the app running after a force-quit or restart.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Override tunnel peer IP (optional)", text: $engine.overridePeer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if !engine.message.isEmpty {
                    Section("Last message") { Text(engine.message).font(.footnote) }
                }
            }
            .navigationTitle("Setup")
            .sheet(isPresented: $showOutsideSetup) { OutsideSetupView().environmentObject(engine) }
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
