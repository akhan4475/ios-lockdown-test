import SwiftUI
import MapKit
import CoreLocation

@MainActor
final class SearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { completer.queryFragment = query }
    }
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    func resolve(_ completion: MKLocalSearchCompletion) async -> (title: String, coordinate: CLLocationCoordinate2D)? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        return (item.name ?? completion.title, item.placemark.coordinate)
    }
}

struct SavedPlace: Codable, Identifiable {
    var id = UUID()
    var name: String
    var lat: Double
    var lon: Double
}

@MainActor
final class SavedStore: ObservableObject {
    @Published var places: [SavedPlace] = [] {
        didSet { persist() }
    }

    private let key = "savedPlaces.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            places = decoded
        }
    }

    func add(name: String, coordinate: CLLocationCoordinate2D) {
        places.insert(SavedPlace(name: name, lat: coordinate.latitude, lon: coordinate.longitude), at: 0)
    }

    func remove(at offsets: IndexSet) {
        places.remove(atOffsets: offsets)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
