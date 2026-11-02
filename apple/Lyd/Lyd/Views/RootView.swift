import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: LydSession

    var body: some View {
        Group {
            switch session.phase {
            case .pickingHost, .connecting, .error:
                HostPickerView()
            case .connected:
                LibraryShellView()
            }
        }
        .onAppear {
            if case .pickingHost = session.phase {
                session.startDiscovery()
            }
        }
    }
}
