import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct Pin: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var coordinate: CLLocationCoordinate2D
}

struct MapScreen: View {
    @EnvironmentObject var engine: LocationEngine
    @StateObject private var search = SearchModel()
    @StateObject private var saved = SavedStore()

    @State private var camera: MapCameraPosition = .automatic
    @State private var pin: Pin?
    @State private var follow = false
    @State private var showSetup = false
    @State private var showSaved = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            mapLayer
            VStack(spacing: 8) {
                topBar
                if searchFocused && !search.query.isEmpty { resultsList }
                if !engine.isReady { statusBanner }
                Spacer()
                bottomCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSetup) { SetupView().environmentObject(engine) }
        .sheet(isPresented: $showSaved) { savedSheet }
        .onReceive(engine.$current) { c in
            guard follow, let c else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                camera = .camera(MapCamera(centerCoordinate: c, distance: 1800))
            }
        }
        .onChange(of: engine.driving) { _, isDriving in
            if isDriving { follow = true }
        }
        .onChange(of: engine.selectedPlan) { _, _ in fitPlans() }
        .onChange(of: engine.plans.count) { _, count in
            if count > 0 { follow = false; fitPlans() }
        }
    }

    // MARK: Map

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let pin {
                    Marker(pin.title, coordinate: pin.coordinate).tint(.red)
                }
                if !engine.plans.isEmpty {
                    ForEach(Array(engine.plans.enumerated()), id: \.element.id) { idx, plan in
                        MapPolyline(coordinates: plan.coords)
                            .stroke(idx == engine.selectedPlan ? Color.blue : Color.gray.opacity(0.7),
                                    lineWidth: idx == engine.selectedPlan ? 6 : 4)
                    }
                } else if engine.route.count > 1 {
                    MapPolyline(coordinates: engine.route).stroke(Color.blue, lineWidth: 6)
                }
                if let c = engine.current {
                    Annotation("You", coordinate: c) {
                        ZStack {
                            Circle().fill(Color.blue.opacity(0.25)).frame(width: 34, height: 34)
                            Circle().fill(Color.blue).frame(width: 16, height: 16)
                            Circle().stroke(Color.white, lineWidth: 3).frame(width: 16, height: 16)
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .mapControls { MapCompass(); MapScaleView() }
            .onTapGesture { searchFocused = false }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        if case .second(true, let drag?) = value,
                           let c = proxy.convert(drag.location, from: .local) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            searchFocused = false
                            select(coordinate: c)
                        }
                    }
            )
        }
        .ignoresSafeArea()
    }

    private func fitPlans() {
        guard engine.plans.indices.contains(engine.selectedPlan) else { return }
        var rect = MKMapRect.null
        for c in engine.plans[engine.selectedPlan].coords {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0)))
        }
        guard !rect.isNull else { return }
        let padded = rect.insetBy(dx: -rect.width * 0.25 - 500, dy: -rect.height * 0.35 - 500)
        withAnimation { camera = .rect(padded) }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search address or place", text: $search.query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !search.query.isEmpty {
                    Button { search.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button { showSaved = true } label: {
                Image(systemName: "star.fill").padding(10)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button { showSetup = true } label: {
                Image(systemName: "gearshape.fill").padding(10)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(search.results.prefix(8), id: \.self) { item in
                    Button {
                        Task { await choose(item) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(engine.status).font(.footnote)
            Spacer()
            Button("Retry") { Task { await engine.bootstrap() } }
                .font(.footnote.weight(.semibold))
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Bottom card

    private var bottomCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !engine.plans.isEmpty {
                    planCard
                } else if engine.driving || engine.paused || engine.route.count > 1 {
                    driveControls
                }

                if let pin, engine.plans.isEmpty {
                    pinCard(pin)
                } else if engine.current == nil && engine.plans.isEmpty {
                    Text("Search for a place, or press and hold on the map to drop a pin.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if !engine.holding, engine.plans.isEmpty, let last = engine.lastLocation {
                    Button {
                        engine.resumeLast()
                        follow = true
                    } label: {
                        Label("Resume last location: \(last.name)", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!engine.isReady || engine.ddiMounted == false)
                }

                if engine.ddiMounted == false && engine.isReady {
                    Button("Mount developer image (needed once per restart)") { showSetup = true }
                        .font(.footnote.weight(.semibold))
                }

                if engine.holding {
                    HStack {
                        Text("Holding. ok \(engine.okCount)  failed \(engine.failCount)")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await engine.clearLocation() }
                        } label: {
                            Text("Clear location").font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                    if !engine.lastError.isEmpty {
                        Text(engine.lastError).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                    }
                }

                if !engine.message.isEmpty {
                    Text(engine.message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func pinCard(_ pin: Pin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.title).font(.headline).lineLimit(2)
                if !pin.subtitle.isEmpty {
                    Text(pin.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(String(format: "%.5f, %.5f", pin.coordinate.latitude, pin.coordinate.longitude))
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button {
                    engine.teleport(to: pin.coordinate, name: pin.title)
                    follow = true
                } label: {
                    Label("Set location", systemImage: "location.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!engine.isReady || engine.ddiMounted == false)

                Button {
                    Task { await engine.planDrive(to: pin.coordinate, name: pin.title) }
                } label: {
                    Label("Drive there", systemImage: "car.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!engine.isReady || engine.current == nil || engine.busy)

                Button {
                    saved.add(name: pin.title, coordinate: pin.coordinate)
                    engine.message = "Saved."
                } label: {
                    Image(systemName: "star")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a route").font(.subheadline.weight(.semibold))
            ForEach(Array(engine.plans.enumerated()), id: \.element.id) { idx, plan in
                Button {
                    engine.selectPlan(idx)
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: idx == engine.selectedPlan ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.name.isEmpty ? "Route \(idx + 1)" : "Via \(plan.name)").font(.subheadline)
                            Text(String(format: "%.1f mi  -  %d min  -  avg %d mph",
                                        plan.distance / 1609.344,
                                        Int((plan.eta / 60).rounded()),
                                        Int(plan.avgMph.rounded())))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("\(Int(engine.speedMph)) mph").font(.caption.monospaced()).frame(width: 60, alignment: .leading)
                Slider(value: $engine.speedMph, in: 5...90, step: 1)
            }
            HStack(spacing: 8) {
                Button("Use route average") { engine.useRouteAverage() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Cancel") { engine.cancelPlan() }
                    .buttonStyle(.bordered)
                Button {
                    engine.beginDrive()
                    follow = true
                } label: {
                    Label("Start drive", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var driveControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(engine.driving ? (engine.paused ? "Paused" : "Driving") : "Route ready")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f mi left", max(engine.routeDistance - engine.traveled, 0) / 1609.344))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: engine.routeDistance > 0 ? engine.traveled / engine.routeDistance : 0)
            HStack {
                Text("\(Int(engine.speedMph)) mph").font(.caption.monospaced()).frame(width: 60, alignment: .leading)
                Slider(value: $engine.speedMph, in: 5...90, step: 1)
            }
            HStack(spacing: 8) {
                Button {
                    engine.paused.toggle()
                } label: {
                    Label(engine.paused ? "Resume" : "Pause", systemImage: engine.paused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!engine.driving)

                Button(role: .destructive) {
                    engine.stopDrive()
                } label: {
                    Label("Stop drive", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    follow.toggle()
                } label: {
                    Image(systemName: follow ? "location.north.line.fill" : "location.north.line")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Saved

    private var savedSheet: some View {
        NavigationStack {
            List {
                if saved.places.isEmpty {
                    Text("No saved places yet. Drop a pin and tap the star.").foregroundStyle(.secondary)
                }
                ForEach(saved.places) { place in
                    Button {
                        let c = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
                        pin = Pin(title: place.name, subtitle: "Saved place", coordinate: c)
                        camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 1500, longitudinalMeters: 1500))
                        showSaved = false
                    } label: {
                        VStack(alignment: .leading) {
                            Text(place.name)
                            Text(String(format: "%.5f, %.5f", place.lat, place.lon))
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { saved.remove(at: $0) }
            }
            .navigationTitle("Saved places")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showSaved = false } } }
        }
    }

    // MARK: Actions

    private func choose(_ completion: MKLocalSearchCompletion) async {
        searchFocused = false
        guard let result = await search.resolve(completion) else {
            engine.message = "Could not look that up."
            return
        }
        search.query = ""
        pin = Pin(title: result.title, subtitle: completion.subtitle, coordinate: result.coordinate)
        follow = false
        camera = .region(MKCoordinateRegion(center: result.coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000))
    }

    private func select(coordinate: CLLocationCoordinate2D) {
        let placeholder = Pin(title: "Dropped pin", subtitle: "", coordinate: coordinate)
        pin = placeholder
        follow = false
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Task {
            guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
            let title = mark.name ?? mark.thoroughfare ?? "Dropped pin"
            let subtitle = [mark.locality, mark.administrativeArea].compactMap { $0 }.joined(separator: ", ")
            if pin?.id == placeholder.id {
                pin = Pin(title: title, subtitle: subtitle, coordinate: coordinate)
            }
        }
    }
}
