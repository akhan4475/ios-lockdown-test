import SwiftUI

@main
struct LockdownTestApp: App {
    @StateObject private var engine = LocationEngine()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _ = SessionAlerts.shared
    }

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environmentObject(engine)
                .preferredColorScheme(.light)
                .task {
                    await SessionAlerts.shared.refreshAuthorization()
                    await engine.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await SessionAlerts.shared.refreshAuthorization() }
                    }
                }
        }
    }
}
