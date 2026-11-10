import XCTest

enum UITestLocale {
    /// The app's source language. Every pre-localization suite is pinned to it
    /// so host/simulator language changes cannot break Chinese assertions.
    static let simplifiedChinese = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    static let english = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
}

extension XCUIApplication {
    /// Launch with an explicit process language. Existing `-AppleLanguages` or
    /// `-AppleLocale` pairs in `launchArguments` are replaced, so call sites can
    /// keep setting their feature flags normally.
    func launchPinned(_ localeArguments: [String] = UITestLocale.simplifiedChinese) {
        var filtered: [String] = []
        var skipNext = false
        for argument in launchArguments {
            if skipNext {
                skipNext = false
                continue
            }
            if argument == "-AppleLanguages" || argument == "-AppleLocale" {
                skipNext = true
                continue
            }
            filtered.append(argument)
        }
        launchArguments = filtered + localeArguments
        launch()
    }
}
