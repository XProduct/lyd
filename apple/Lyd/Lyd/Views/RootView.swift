import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: LydSession
    @State private var didBootstrap = false

    var body: some View {
        LibraryShellView()
            .onAppear {
                guard !didBootstrap else { return }
                didBootstrap = true
                session.startDiscovery()
                session.reconnectLastIfPossible()
            }
    }
}
