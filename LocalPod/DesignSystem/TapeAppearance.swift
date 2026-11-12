import SwiftUI
import UIKit

/// One-time UIKit appearance setup. SwiftUI's navigation bar and search field
/// are still system controls (UI tests depend on `navigationBars["…"]` and the
/// search field), so their chrome is themed through UIAppearance.
enum TapeAppearance {
    @MainActor
    static func configure() {
        let ink = UIColor(TapeTheme.ink)
        let cream = UIColor(TapeTheme.cream)
        let titleFont = UIFont(name: "SpaceGrotesk-Bold", size: 18)
            ?? UIFont.systemFont(ofSize: 18, weight: .bold)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = cream
        navigation.shadowColor = ink.withAlphaComponent(0.24)
        navigation.titleTextAttributes = [
            .foregroundColor: ink,
            .font: titleFont
        ]
        navigation.largeTitleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFont(name: "SpaceGrotesk-Bold", size: 33)
                ?? UIFont.systemFont(ofSize: 33, weight: .bold)
        ]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = navigation
        bar.scrollEdgeAppearance = navigation
        bar.compactAppearance = navigation
        bar.tintColor = ink

        // The system tab bar is hidden in RootView; its appearance is still
        // configured so any sheet-presented hierarchy stays on-palette during
        // transitions.
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = cream
        tabAppearance.shadowColor = ink
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        UISearchBar.appearance().tintColor = ink
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).backgroundColor =
            UIColor(TapeTheme.card)
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).textColor = ink

        UISwitch.appearance().onTintColor = UIColor(TapeTheme.acid)
    }
}
