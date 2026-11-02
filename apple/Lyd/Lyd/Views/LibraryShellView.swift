import SwiftUI

struct LibraryShellView: View {
    var body: some View {
        TabView {
            NavigationStack {
                AlbumsView()
            }
            .tabItem { Label("Albums", systemImage: "square.stack") }

            NavigationStack {
                SongsView()
            }
            .tabItem { Label("Songs", systemImage: "music.note.list") }

            NavigationStack {
                NowPlayingView()
            }
            .tabItem { Label("Now Playing", systemImage: "play.circle") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
