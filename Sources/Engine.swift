import SwiftUI
import MapKit
import CoreLocation
import Minimuxer

extension MKPolyline {
    var coords: [CLLocationCoordinate2D] {
        var arr = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&arr, range: NSRange(location: 0, length: pointCount))
        return arr
    }
}

struct LastLocation: Codable {
    var lat: Double
    var lon: Double
    var name: String
}

struct PlannedRoute: Identifiable {
    let id = UUID()
    let name: String
    let coords: [CLLocationCoordinate2D]
    let distance: Double
    let eta: Double
    var avgMph: Double { eta > 0 ? distance / eta / 0.44704 : 30 }
}

@MainActor
final class LocationEngine: ObservableObject {
    @Published var status = "Starting..."
    @Published var isReady = false
    @Published var ddiMounted: Bool? = nil
    @Published var pairingName: String? = nil
    @Published var busy = false
    @Published var message = ""

    @Published var current: CLLocationCoordinate2D?
    @Published var holding = false
    @Published var route: [CLLocationCoordinate2D] = []
    @Published var routeDistance: Double = 0
    @Published var traveled: Double = 0
    @Published var driving = false
    @Published var paused = false
    @Published var speedMph: Double = 45

    @Published var plans: [PlannedRoute] = []
    @Published var selectedPlan = 0
    @Published var lastLocation: LastLocation?

    @Published var okCount = 0
    @Published var failCount = 0
    @Published var lastError = ""

    @Published var keepAlive = true
    @Published var overridePeer: String = UserDefaults.standard.string(forKey: "overridePeer") ?? "" {
        didSet { UserDefaults.standard.set(overridePeer, forKey: "overridePeer") }
    }

    private var ticker: Task<Void, Never>?
    private var cumulative: [Double] = []
    private var lastTick = Date()
    private let realLocation = RealLocation()
    private var destName = ""
    private var lastSave = Date.distantPast
    private let lastKey = "lastLocation.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: lastKey),
           let decoded = try? JSONDecoder().decode(LastLocation.self, from: data) {
            lastLocation = decoded
        }
    }

    private var docsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: Pairing file

    func findPairingFile() -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)) ?? []
        let candidates = files.filter { ["plist", "mobiledevicepairing"].contains($0.pathExtension.lowercased()) }
        return candidates.first(where: { $0.lastPathComponent == "pairingFile.plist" }) ?? candidates.first
    }

    func importPairingFile(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = docsURL.appendingPathComponent("pairingFile.plist")
        if url.standardizedFileURL.path == dest.standardizedFileURL.path {
            message = "That file is already in the app. Nothing changed."
            return
        }
        let temp = docsURL.appendingPathComponent("pairingFile.import.tmp")
        do {
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: url, to: temp)
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.moveItem(at: temp, to: dest)
            message = "Pairing file saved in the app."
        } catch {
            message = "Could not import file: \(error.localizedDescription)"
        }
    }

    func deletePairingFile() {
        if let url = findPairingFile() { try? FileManager.default.removeItem(at: url) }
        pairingName = nil
        isReady = false
        status = "Pairing file removed."
    }

    private func excludeFromBackup(_ url: URL) {
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
    }

    // MARK: Connection

    func bootstrap() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        isReady = false

        guard let url = findPairingFile(), let text = try? String(contentsOf: url, encoding: .utf8) else {
            pairingName = nil
            status = "No pairing file. Open Setup and choose one."
            return
        }
        pairingName = url.lastPathComponent
        excludeFromBackup(url)

        let peer = overridePeer.trimmingCharacters(in: .whitespaces)
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

        status = "Connecting..."
        await core.bindConnectionConfig(binding)
        do {
            try await core.start(pairingFile: text, mountPath: docsURL.path, preferred: .rppairing)
        } catch {
            status = "Start failed: \(error)"
            return
        }

        let ready = await core.isReady(withNetworkCheck: false, withDDIMountCheck: false)
        if case .failure(let err) = ready {
            status = "Not connected: \(core.describeError(err)). Is LocalDevVPN on?"
            return
        }

        ddiMounted = try? await core.isDDIMounted()
        isReady = true
        status = ddiMounted == false ? "Connected. Developer image not mounted (see Setup)." : "Ready"
    }

    func mountDDI() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        message = "Mounting developer image (may take a minute)..."
        do {
            let didMount = try await Minimuxer.shared.core.mountDDI(docsPath: docsURL.path)
            ddiMounted = true
            message = didMount ? "Developer image mounted." : "It was already mounted."
            if isReady { status = "Ready" }
        } catch {
            message = "Mount failed: \(error)"
        }
    }

    // MARK: Teleport / hold

    func teleport(to coordinate: CLLocationCoordinate2D, name: String = "Teleported location") {
        stopDrive()
        cancelPlan()
        current = coordinate
        remember(coordinate, name: name)
        startTicker()
    }

    func resumeLast() {
        guard let last = lastLocation else { return }
        teleport(to: CLLocationCoordinate2D(latitude: last.lat, longitude: last.lon), name: last.name)
    }

    private func remember(_ c: CLLocationCoordinate2D, name: String) {
        let last = LastLocation(lat: c.latitude, lon: c.longitude, name: name)
        lastLocation = last
        if let data = try? JSONEncoder().encode(last) {
            UserDefaults.standard.set(data, forKey: lastKey)
        }
    }

    private func startTicker() {
        ticker?.cancel()
        holding = true
        okCount = 0
        failCount = 0
        lastError = ""
        if keepAlive { KeepAlive.shared.start() }
        lastTick = Date()
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                let now = Date()
                let dt = now.timeIntervalSince(self.lastTick)
                self.lastTick = now
                self.advance(dt: dt)
                if let c = self.current { await self.send(c) }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func send(_ c: CLLocationCoordinate2D) async {
        do {
            try await Minimuxer.shared.core.setSimulatedLocation(latitude: c.latitude, longitude: c.longitude)
            okCount += 1
            lastError = ""
        } catch {
            failCount += 1
            lastError = "\(error)"
        }
    }

    func clearLocation() async {
        ticker?.cancel()
        await ticker?.value
        ticker = nil
        holding = false
        driving = false
        paused = false
        route = []
        plans = []
        current = nil
        KeepAlive.shared.stop()
        do {
            try await Minimuxer.shared.core.clearSimulatedLocation()
            message = "Real GPS restored."
        } catch {
            message = "Clear failed: \(error)"
        }
    }

    // MARK: Driving

    func planDrive(to destination: CLLocationCoordinate2D, name: String) async {
        busy = true
        defer { busy = false }

        let start: CLLocationCoordinate2D
        if let c = current {
            start = c
        } else {
            message = "Reading your real location..."
            guard let real = await realLocation.fetch() else {
                message = "Could not read your real location. Allow Location for this app in Settings, or Set location somewhere first."
                return
            }
            start = real
        }
        message = "Finding routes..."

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        do {
            let response = try await MKDirections(request: request).calculate()
            var list: [PlannedRoute] = []
            for r in response.routes.prefix(3) {
                let pts = r.polyline.coords
                if pts.count > 1 {
                    list.append(PlannedRoute(name: r.name, coords: pts, distance: r.distance, eta: r.expectedTravelTime))
                }
            }
            guard !list.isEmpty else {
                message = "No driving route found."
                return
            }
            plans = list
            selectedPlan = 0
            speedMph = clampedSpeed(list[0].avgMph)
            destName = name
            message = ""
        } catch {
            message = "Route failed: \(error.localizedDescription)"
        }
    }

    func selectPlan(_ index: Int) {
        guard plans.indices.contains(index) else { return }
        selectedPlan = index
        speedMph = clampedSpeed(plans[index].avgMph)
    }

    func useRouteAverage() {
        guard plans.indices.contains(selectedPlan) else { return }
        speedMph = clampedSpeed(plans[selectedPlan].avgMph)
    }

    func cancelPlan() {
        plans = []
    }

    func beginDrive() {
        guard plans.indices.contains(selectedPlan) else { return }
        route = plans[selectedPlan].coords
        if current == nil { current = route.first }
        plans = []
        buildCumulative()
        traveled = 0
        paused = false
        driving = true
        message = ""
        startTicker()
    }

    func stopDrive() {
        driving = false
        paused = false
        route = []
        traveled = 0
    }

    private func clampedSpeed(_ mph: Double) -> Double {
        min(max(mph.rounded(), 5), 90)
    }

    private func buildCumulative() {
        cumulative = [0]
        var total = 0.0
        for i in 1..<route.count {
            let a = CLLocation(latitude: route[i - 1].latitude, longitude: route[i - 1].longitude)
            let b = CLLocation(latitude: route[i].latitude, longitude: route[i].longitude)
            total += a.distance(from: b)
            cumulative.append(total)
        }
        routeDistance = total
    }

    private func advance(dt: Double) {
        guard driving, !paused, route.count > 1 else { return }
        traveled += speedMph * 0.44704 * dt
        if traveled >= routeDistance {
            traveled = routeDistance
            if let end = route.last {
                current = end
                remember(end, name: destName.isEmpty ? "Destination" : destName)
            }
            driving = false
            message = "Arrived."
            return
        }
        let here = point(at: traveled)
        current = here
        if Date().timeIntervalSince(lastSave) > 5 {
            lastSave = Date()
            remember(here, name: destName.isEmpty ? "Last drive position" : "On the way to \(destName)")
        }
    }

    private func point(at distance: Double) -> CLLocationCoordinate2D {
        var lo = 0
        var hi = cumulative.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= distance { lo = mid } else { hi = mid }
        }
        let segment = cumulative[hi] - cumulative[lo]
        let t = segment > 0 ? (distance - cumulative[lo]) / segment : 0
        let a = route[lo]
        let b = route[hi]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }
}
