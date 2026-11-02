import SwiftUI

@main
struct LydApp: App {
    @StateObject private var session = LydSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                #if os(iOS)
                .tint(LydTheme.primary)
                .accentColor(LydTheme.primary)
                #endif
                .onChange(of: scenePhase) { _, newPhase in
                    session.handleScenePhase(newPhase)
                }
        }
    }
}
