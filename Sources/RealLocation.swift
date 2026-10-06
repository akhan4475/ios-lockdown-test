import CoreLocation

@MainActor
final class RealLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func fetch() async -> CLLocationCoordinate2D? {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        default:
            break
        }
        finish(nil)
        return await withCheckedContinuation { cont in
            continuation = cont
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                self.finish(nil)
            }
        }
    }

    private func finish(_ value: CLLocationCoordinate2D?) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.continuation != nil { self.manager.requestLocation() }
            case .denied, .restricted:
                self.finish(nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let c = locations.last?.coordinate
        Task { @MainActor in self.finish(c) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
