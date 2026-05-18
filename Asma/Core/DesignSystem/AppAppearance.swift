import SwiftUI
import UIKit

@MainActor
enum AppAppearance {
    static func configure() {
        configureNavigationBar()
        configureTabBar()
        configurePageControl()
        configureWindow()
    }

    /// Paints the window backdrop so any system-managed area
    /// (under the iOS 26 floating tab bar etc.) inherits the app's dark base
    /// instead of falling back to UIKit's default systemBackground.
    private static func configureWindow() {
        let base = UIColor(AsmaColor.bgCream)
        UIWindow.appearance().backgroundColor = base
        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.windows.first }
                .forEach { $0.backgroundColor = base }
        }
    }

    private static func configureNavigationBar() {
        let primary = UIColor(AsmaColor.textPrimary)
        let base = UIColor(AsmaColor.bgCream)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: primary,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        let largeTitleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: primary,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
        ]

        // Opaque dark bar when scrolling under it.
        let opaque = UINavigationBarAppearance()
        opaque.configureWithOpaqueBackground()
        opaque.backgroundColor = base
        opaque.shadowColor = .clear
        opaque.titleTextAttributes = titleAttrs
        opaque.largeTitleTextAttributes = largeTitleAttrs

        // Transparent at scroll-top so large titles sit on the page.
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.backgroundColor = .clear
        edge.shadowColor = .clear
        edge.titleTextAttributes = titleAttrs
        edge.largeTitleTextAttributes = largeTitleAttrs

        let nav = UINavigationBar.appearance()
        nav.standardAppearance = opaque
        nav.compactAppearance = opaque
        nav.scrollEdgeAppearance = edge
        nav.compactScrollEdgeAppearance = edge
        nav.tintColor = UIColor(AsmaColor.brandGold)
        nav.prefersLargeTitles = true
    }

    private static func configureTabBar() {
        let secondary = UIColor(AsmaColor.textSecondary)
        let accent = UIColor(AsmaColor.brandGold)

        // Default background — on iOS 26 this becomes Liquid Glass capsule,
        // on iOS 17/18 it's a system blur. Either way it sits naturally on the
        // dark app background.
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.shadowColor = .clear

        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = secondary
            layout.normal.titleTextAttributes = [.foregroundColor: secondary]
            layout.selected.iconColor = accent
            layout.selected.titleTextAttributes = [.foregroundColor: accent]
        }

        let tab = UITabBar.appearance()
        tab.standardAppearance = appearance
        tab.scrollEdgeAppearance = appearance
        tab.tintColor = accent
        tab.unselectedItemTintColor = secondary
    }

    private static func configurePageControl() {
        let accent = UIColor(AsmaColor.brandGold)
        UIPageControl.appearance().currentPageIndicatorTintColor = accent
        UIPageControl.appearance().pageIndicatorTintColor = accent.withAlphaComponent(0.25)
    }
}
