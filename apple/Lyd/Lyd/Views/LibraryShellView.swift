import SwiftUI

struct LibraryShellView: View {
    @EnvironmentObject private var session: LydSession

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
        .tint(LydTheme.primary)
    }
}
