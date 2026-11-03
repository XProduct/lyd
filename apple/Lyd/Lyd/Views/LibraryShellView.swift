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
        // `.toolbar(.hidden, for: .tabBar)` does nothing to tvOS TabView chrome — hide the
        // real UITabBar via UIKit when idle cinema is active.
        .background {
            TVTabBarVisibilityBridge(hidden: session.isNowPlayingCinemaActive)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onChange(of: session.isNowPlayingCinemaActive) { _, hidden in
            // Re-assert after SwiftUI layout passes that tend to resurrect the bar.
            TVTabBarVisibilityBridge.setHidden(hidden)
        }
        #endif
    }
}
