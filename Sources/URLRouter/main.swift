import AppKit

let args = Array(CommandLine.arguments.dropFirst())

// `--profiles [appPath]`: list profiles for a browser (default: the configured default browser).
if let i = args.firstIndex(of: "--profiles") {
    let appPath = (i + 1 < args.count && !args[i + 1].hasPrefix("-"))
        ? args[i + 1]
        : ConfigStore.shared.load().resolvedDefaultApp
    print("\(BrowserFinder.name(forPath: appPath))  (\(appPath))")
    let profiles = Browsers.profiles(for: appPath)
    if profiles.isEmpty {
        print(Browsers.supportsProfiles(appPath)
            ? "  (no profiles found)"
            : "  (this browser doesn't support profile selection)")
    } else {
        for p in profiles {
            let suffix = p.key == p.label ? "" : "  [key: \(p.key)]"
            print("  • \(p.label)\(suffix)")
        }
    }
    exit(0)
}

// `--dry-run <url>`: print the routing decision without launching anything.
if let i = args.firstIndex(of: "--dry-run"), i + 1 < args.count, let url = URL(string: args[i + 1]) {
    let config = ConfigStore.shared.load()
    let decision = RuleEngine.decide(url: url, config: config)
    print("URL:     \(url.absoluteString)")
    print("Rule:    \(decision.matchedRule?.name ?? "(default fallback)")")
    print("App:     \(decision.app)")
    print("Profile: \(decision.profile ?? "(app default)")")
    let openModeNote = Browsers.supportsOpenMode(decision.app)
        ? decision.openMode.label
        : "\(decision.openMode.label) (ignored — browser has no CLI control)"
    print("Open in: \(openModeNote)")
    exit(0)
}

// A URL passed directly on the command line (e.g. `open 'URL Router.app' --args https://…`)
// is routed immediately — handy for testing before setting it as the default browser.
if let url = args.first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") })
    .flatMap({ URL(string: $0) }) {
    let config = ConfigStore.shared.load()
    Launcher.launch(url: url, decision: RuleEngine.decide(url: url, config: config))
    exit(0)
}

// Otherwise run as a normal app: GetURL events route in the background; a direct
// launch opens the SwiftUI rules editor.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
