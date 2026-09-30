import Foundation

enum Launcher {
    /// Launches the routed browser/profile with the URL.
    @discardableResult
    static func launch(url: URL, decision: RouteDecision) -> Bool {
        Browsers.launch(appPath: decision.app, profileKey: decision.profile,
                        openMode: decision.openMode, url: url)
    }
}
