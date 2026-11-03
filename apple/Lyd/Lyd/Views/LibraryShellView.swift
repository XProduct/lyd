import SwiftUI
#if os(tvOS)
import UIKit
#endif

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

#if os(tvOS)
/// SwiftUI `.toolbar(.hidden, for: .tabBar)` is a no-op on Apple TV's TabView chrome.
/// Find the real `UITabBar` / `UITabBarController` and hide them for idle cinema.
/// Kept in this file so the type is always in the same target/module as `LibraryShellView`.
private struct TVTabBarVisibilityBridge: UIViewControllerRepresentable {
    var hidden: Bool

    static func setHidden(_ hidden: Bool) {
        DispatchQueue.main.async {
            applyGlobally(hidden: hidden)
        }
        if hidden {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                applyGlobally(hidden: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                applyGlobally(hidden: true)
            }
        }
    }

    func makeUIViewController(context: Context) -> BridgeController {
        BridgeController()
    }

    func updateUIViewController(_ controller: BridgeController, context: Context) {
        controller.apply(hidden: hidden)
    }

    fileprivate static func applyGlobally(hidden: Bool, preferring preferred: UITabBarController? = nil) {
        var seen = Set<ObjectIdentifier>()

        func style(_ tabBar: UITabBar) {
            let id = ObjectIdentifier(tabBar)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            styleTabBar(tabBar, hidden: hidden)
        }

        if let tab = preferred {
            style(tab.tabBar)
        }

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let root = window.rootViewController {
                    for tab in root.lyd_allTabBarControllers() {
                        style(tab.tabBar)
                    }
                }
                for bar in window.lyd_allTabBars() {
                    style(bar)
                }
            }
        }
    }

    private static var savedFrames: [ObjectIdentifier: CGRect] = [:]

    private static func styleTabBar(_ tabBar: UITabBar, hidden: Bool) {
        let id = ObjectIdentifier(tabBar)
        if hidden {
            if savedFrames[id] == nil {
                savedFrames[id] = tabBar.frame
            }
            tabBar.isHidden = true
            tabBar.alpha = 0
            tabBar.isUserInteractionEnabled = false
            var frame = tabBar.frame
            if frame.height > 0 {
                frame.origin.y = -frame.height - 80
                tabBar.frame = frame
            }
        } else {
            tabBar.isHidden = false
            tabBar.alpha = 1
            tabBar.isUserInteractionEnabled = true
            if let saved = savedFrames.removeValue(forKey: id) {
                tabBar.frame = saved
            }
        }
    }

    final class BridgeController: UIViewController {
        private var lastHidden: Bool?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if let lastHidden {
                apply(hidden: lastHidden)
            }
        }

        func apply(hidden: Bool) {
            lastHidden = hidden
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let tab = self.tabBarController ?? Self.nearestTabBarController(from: self)
                TVTabBarVisibilityBridge.applyGlobally(hidden: hidden, preferring: tab)
            }
        }

        private static func nearestTabBarController(from start: UIViewController) -> UITabBarController? {
            var current: UIViewController? = start
            while let c = current {
                if let tab = c as? UITabBarController { return tab }
                if let tab = c.tabBarController { return tab }
                current = c.parent ?? c.presentingViewController
            }
            return nil
        }
    }
}

private extension UIView {
    func lyd_allTabBars() -> [UITabBar] {
        var result: [UITabBar] = []
        if let tabBar = self as? UITabBar {
            result.append(tabBar)
        }
        for sub in subviews {
            result.append(contentsOf: sub.lyd_allTabBars())
        }
        return result
    }
}

private extension UIViewController {
    func lyd_allTabBarControllers() -> [UITabBarController] {
        var result: [UITabBarController] = []
        if let tab = self as? UITabBarController {
            result.append(tab)
        }
        for child in children {
            result.append(contentsOf: child.lyd_allTabBarControllers())
        }
        if let presented = presentedViewController {
            result.append(contentsOf: presented.lyd_allTabBarControllers())
        }
        return result
    }
}
#endif
