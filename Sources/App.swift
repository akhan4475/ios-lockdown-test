import SwiftUI

@main
struct LockdownTestApp: App {
    @StateObject private var engine = LocationEngine()

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environmentObject(engine)
                .preferredColorScheme(.light)
                .task { await engine.bootstrap() }
        }
    }
}
