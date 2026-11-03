import SwiftUI

private struct CoverMorphNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var coverMorphNamespace: Namespace.ID? {
        get { self[CoverMorphNamespaceKey.self] }
        set { self[CoverMorphNamespaceKey.self] = newValue }
    }
}

struct LibraryShellView: View {
    @EnvironmentObject private var session: LydSession
    @Namespace private var coverMorph

    var body: some View {
        TabView(selection: $session.selectedTab) {
            NavigationStack {
                AlbumsView()
            }
            .tabItem { Label("Albums", systemImage: "square.stack") }
            .tag(AppTab.albums)

            NavigationStack {
                SongsView()
            }
            .tabItem { Label("Songs", systemImage: "music.note.list") }
            .tag(AppTab.songs)

            NavigationStack {
                NowPlayingView()
            }
            .tabItem { Label("Now Playing", systemImage: "play.circle") }
            .tag(AppTab.nowPlaying)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .environment(\.coverMorphNamespace, coverMorph)
        #if os(iOS)
        .tint(LydTheme.primary)
        #else
        // System tab bar selection colors on tvOS (no Lyd purple).
        .tint(.primary)
        // Idle cinema: hide the tab bar for a true full-screen Now Playing stage.
        .toolbar(session.isNowPlayingCinemaActive ? .hidden : .automatic, for: .tabBar)
        .animation(.easeInOut(duration: 0.35), value: session.isNowPlayingCinemaActive)
        #endif
    }
}
