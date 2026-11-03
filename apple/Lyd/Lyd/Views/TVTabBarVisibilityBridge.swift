#if os(tvOS)
import SwiftUI
import UIKit

/// SwiftUI `.toolbar(.hidden, for: .tabBar)` is a no-op on Apple TV's TabView chrome.
/// Walk the real UIKit tab bars and hide/show them for idle cinema.
struct TVTabBarVisibilityBridge: UIViewControllerRepresentable {
    var hidden: Bool

    /// Apply from anywhere (e.g. `onChange`) — window walk does not need a hosted VC.
    static func setHidden(_ hidden: Bool) {
        DispatchQueue.main.async {
            applyToWindows(hidden: hidden)
        }
    }

    func makeUIViewController(context: Context) -> BridgeController {
        BridgeController()
    }

    func updateUIViewController(_ controller: BridgeController, context: Context) {
        controller.apply(hidden: hidden)
    }

    fileprivate static func applyToWindows(hidden: Bool, preferring preferred: UITabBarController? = nil) {
        var bars = Set<ObjectIdentifier>()

        if let tab = preferred {
            style(tabBar: tab.tabBar, hidden: hidden)
            bars.insert(ObjectIdentifier(tab.tabBar))
        }

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                for bar in window.lyd_allTabBars() where !bars.contains(ObjectIdentifier(bar)) {
                    style(tabBar: bar, hidden: hidden)
                    bars.insert(ObjectIdentifier(bar))
                }
            }
        }
    }

    private static func style(tabBar: UITabBar, hidden: Bool) {
        // isHidden removes it from the focus engine — correct for cinema (we focus the stage).
        tabBar.isHidden = hidden
        tabBar.alpha = hidden ? 0 : 1
        tabBar.isUserInteractionEnabled = !hidden
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
            // Defer one turn so SwiftUI finishes hosting the TabView before we hunt chrome.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let tab = self.tabBarController ?? Self.nearestTabBarController(from: self)
                TVTabBarVisibilityBridge.applyToWindows(hidden: hidden, preferring: tab)
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
        // SwiftUI/tvOS sometimes wraps the bar; still match by class name.
        let typeName = String(describing: type(of: self))
        if !(self is UITabBar),
           typeName.contains("UITabBar"),
           !typeName.contains("Button"),
           !typeName.contains("Item") {
            // Private container — hide the view itself via associated UITabBar children only.
        }
        for sub in subviews {
            result.append(contentsOf: sub.lyd_allTabBars())
        }
        return result
    }
}
#endif
