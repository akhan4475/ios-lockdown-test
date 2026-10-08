import SwiftUI
import CoreLocation

struct OutsideSetupView: View {
    @EnvironmentObject var engine: LocationEngine
    @Environment(\.dismiss) private var dismiss
    @State private var latitude = ""
    @State private var longitude = ""

    private var canRestoreData: Bool {
        OutsideStartupPolicy.canRestoreData(
            holding: engine.holding, acknowledgements: engine.okCount,
            lastError: engine.lastError
        )
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              OutsideStartupPolicy.validCoordinates(latitude: lat, longitude: lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("1. Connect LocalDevVPN") {
                    Text("Open LocalDevVPN and connect it. Return here and leave Wi-Fi off.")
                    Text("You need the pairing file already saved in this app. After a phone restart, the developer image also needs mounting again.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("2. Temporarily turn mobile data off") {
                    Text("In Control Center, turn Mobile Data off. Keep LocalDevVPN connected, then return here. The app cannot change this setting for you.")
                    Button(engine.busy ? "Connecting..." : "Mobile data is off — Connect") {
                        Task { await engine.bootstrap(attempts: 3) }
                    }
                    .disabled(engine.busy || engine.holding)
                    Text(engine.status).font(.footnote).textSelection(.enabled)
                    if engine.ddiMounted == false && engine.isReady {
                        Button("Mount developer image") {
                            Task { await engine.mountDDI() }
                        }
                        .disabled(engine.busy)
                        Text("Mounting may need internet. If it fails offline, turn mobile data back on for the download while leaving LocalDevVPN connected, then retry. Preparing this once at home is simplest.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("3. Start the fixed location") {
                    if let last = engine.lastLocation {
                        Button("Resume: \(last.name)") { engine.resumeLast() }
                            .disabled(!engine.isReady || engine.ddiMounted == false || engine.busy || engine.holding)
                    }
                    TextField("Latitude (−90 to 90)", text: $latitude)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Longitude (−180 to 180)", text: $longitude)
                        .keyboardType(.numbersAndPunctuation)
                    Button("Set these coordinates") {
                        if let coordinate {
                            engine.teleport(to: coordinate, name: "Outside test location")
                        }
                    }
                    .disabled(coordinate == nil || !engine.isReady || engine.ddiMounted == false || engine.busy || engine.holding)
                    Text("Resume and coordinates work without internet. Once mobile data is back on, you can search or change the location on the map.")
                        .font(.caption).foregroundStyle(.secondary)
                    if engine.holding {
                        Text("Successful commands: \(engine.okCount) · Failed: \(engine.failCount)")
                            .font(.footnote.monospaced())
                    }
                    if !engine.lastError.isEmpty {
                        Text(engine.lastError).foregroundStyle(.orange)
                            .font(.footnote).textSelection(.enabled)
                    }
                }

                Section("4. Turn mobile data back on") {
                    if canRestoreData {
                        Label("The location command succeeded. Turn Mobile Data back on now.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Keep LocalDevVPN connected. Do not press Reconnect. Confirm the successful-command count continues increasing and check the position in Maps.")
                        Button("Return to map") { dismiss() }
                    } else {
                        Text("Wait for a successful location command before turning mobile data back on. A connected VPN or a Ready message alone is not enough.")
                    }
                    Text("If connecting with Mobile Data off fails, try Airplane Mode with Wi-Fi off, reconnect LocalDevVPN if needed, and repeat steps 2–3. Turn Airplane Mode off only after a successful location command. This startup flow still needs testing on your phone.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !engine.message.isEmpty {
                    Section("Last message") { Text(engine.message).font(.footnote).textSelection(.enabled) }
                }
            }
            .navigationTitle("Start without Wi-Fi")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
    }
}
