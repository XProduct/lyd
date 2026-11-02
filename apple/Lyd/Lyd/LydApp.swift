import SwiftUI

@main
struct LydApp: App {
    @StateObject private var session = LydSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}
