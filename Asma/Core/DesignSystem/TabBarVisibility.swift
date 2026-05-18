import SwiftUI
import UIKit

/// Drop-in replacement for `.toolbar(.hidden, for: .tabBar)` that hides the
/// underlying `UITabBar` instantly on push and restores it instantly on pop.
///
/// SwiftUI's built-in `.toolbar(.hidden, for: .tabBar)` triggers a UIKit
/// tab-bar visibility animation that runs *after* the navigation pop
/// completes — so the tab bar appears to slide in late. By hooking
/// `viewWillAppear` / `viewWillDisappear` on a tiny invisible controller
/// embedded in the SwiftUI tree we toggle `tabBar.isHidden` in lock-step
/// with the nav transition, which removes the lag entirely.
extension View {
    /// Hide the tab bar while this view is on screen. Restores visibility
    /// the moment the view disappears (e.g. nav pop, dismiss).
    func hideTabBar() -> some View {
        background(TabBarHider().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}

private struct TabBarHider: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TabBarHiderVC { TabBarHiderVC() }
    func updateUIViewController(_ vc: TabBarHiderVC, context: Context) {}
}

private final class TabBarHiderVC: UIViewController {
    private var didHide = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let bar = findTabBar(), !bar.isHidden {
            bar.isHidden = true
            didHide = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if didHide, let bar = findTabBar() {
            bar.isHidden = false
            didHide = false
        }
    }

    /// Walk up the controller chain (parent chain), then over to the
    /// presenting / window root, looking for the nearest UITabBar.
    /// SwiftUI's TabView is backed by a UITabBarController somewhere up
    /// the tree, but the exact path depends on how the host wrapped us.
    private func findTabBar() -> UITabBar? {
        var node: UIViewController? = self
        while let cur = node {
            if let tbc = cur as? UITabBarController { return tbc.tabBar }
            if let tbc = cur.tabBarController { return tbc.tabBar }
            node = cur.parent
        }
        // Fall back to walking the key window's view hierarchy.
        if let window = view.window ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }),
            let bar = findTabBar(in: window) {
            return bar
        }
        return nil
    }

    private func findTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for sub in view.subviews {
            if let bar = findTabBar(in: sub) { return bar }
        }
        return nil
    }
}
