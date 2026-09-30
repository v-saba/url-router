import Foundation

/// A profile offered to the user. `key` is what gets stored in config and handed back to
/// the adapter to launch; `label` is what the UI shows (they differ for Chromium, where the
/// key is the on-disk directory and the label is the — possibly duplicated — display name).
struct BrowserProfile: Identifiable, Hashable {
    var key: String
    var label: String
    var id: String { key }
}

struct LaunchSpec {
    var executable: String
    var arguments: [String]
}

/// Per-browser strategy for listing profiles and building a launch command.
protocol BrowserAdapter {
    func handles(appPath: String) -> Bool
    var hasProfileSupport: Bool { get }
    /// Whether the browser can honor a new-tab/new-window preference via its CLI.
    var hasOpenModeSupport: Bool { get }
    func profiles(appPath: String) -> [BrowserProfile]
    func launchSpec(appPath: String, profileKey: String?, openMode: OpenMode, url: URL) -> LaunchSpec
}

// MARK: - Registry

enum Browsers {
    private static let adapters: [BrowserAdapter] = [FirefoxAdapter(), ChromiumAdapter()]

    static func adapter(for appPath: String) -> BrowserAdapter {
        adapters.first { $0.handles(appPath: appPath) } ?? GenericAdapter()
    }

    static func profiles(for appPath: String) -> [BrowserProfile] {
        adapter(for: appPath).profiles(appPath: appPath)
    }

    static func supportsProfiles(_ appPath: String) -> Bool {
        adapter(for: appPath).hasProfileSupport
    }

    static func supportsOpenMode(_ appPath: String) -> Bool {
        adapter(for: appPath).hasOpenModeSupport
    }

    @discardableResult
    static func launch(appPath: String, profileKey: String?, openMode: OpenMode, url: URL) -> Bool {
        let spec = adapter(for: appPath).launchSpec(
            appPath: appPath, profileKey: profileKey, openMode: openMode, url: url)
        return ProcessRunner.run(spec)
    }
}

// MARK: - Shared bundle helpers

enum BundleInfo {
    private static func infoDict(_ appPath: String) -> NSDictionary? {
        NSDictionary(contentsOfFile: appPath + "/Contents/Info.plist")
    }

    static func identifier(_ appPath: String) -> String? {
        infoDict(appPath)?["CFBundleIdentifier"] as? String
    }

    static func executable(_ appPath: String) -> String {
        if let exe = infoDict(appPath)?["CFBundleExecutable"] as? String { return exe }
        return (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }

    /// Path to the actual Mach-O binary inside the bundle.
    static func binary(_ appPath: String) -> String {
        appPath + "/Contents/MacOS/" + executable(appPath)
    }
}

enum ProcessRunner {
    @discardableResult
    static func run(_ spec: LaunchSpec) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: spec.executable)
        process.arguments = spec.arguments
        do {
            try process.run()
            return true
        } catch {
            FileHandle.standardError.write(
                Data("URLRouter: failed to launch \(spec.executable): \(error)\n".utf8))
            return false
        }
    }
}

// MARK: - Firefox

struct FirefoxAdapter: BrowserAdapter {
    var hasProfileSupport: Bool { true }
    var hasOpenModeSupport: Bool { true }

    func handles(appPath: String) -> Bool {
        if let id = BundleInfo.identifier(appPath) { return id.hasPrefix("org.mozilla.") }
        return appPath.lowercased().contains("firefox")
    }

    func profiles(appPath: String) -> [BrowserProfile] {
        FirefoxProfiles.list().map { BrowserProfile(key: $0.name, label: $0.name) }
    }

    func launchSpec(appPath: String, profileKey: String?, openMode: OpenMode, url: URL) -> LaunchSpec {
        var args: [String] = []
        if let key = profileKey, !key.isEmpty {
            // Resolve the name to its directory and use --profile (robust on Firefox 151+);
            // fall back to the legacy -P for names not found in the profile stores.
            if let path = FirefoxProfiles.path(forName: key) {
                args += ["--profile", path]
            } else {
                args += ["-P", key]
            }
        }
        let openFlag = openMode == .newWindow ? "-new-window" : "-new-tab"
        args += [openFlag, url.absoluteString]
        return LaunchSpec(executable: BundleInfo.binary(appPath), arguments: args)
    }
}

// MARK: - Chromium family (Chrome, Edge, Brave, Chromium, Vivaldi, Comet, …)

struct ChromiumAdapter: BrowserAdapter {
    var hasProfileSupport: Bool { true }
    var hasOpenModeSupport: Bool { true }

    /// Maps a bundle identifier to its user-data directory under ~/Library/Application Support.
    private static let userDataDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "org.chromium.Chromium": "Chromium",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "ai.perplexity.comet": "Comet",
    ]

    func handles(appPath: String) -> Bool {
        guard let id = BundleInfo.identifier(appPath) else { return false }
        return ChromiumAdapter.userDataDirs[id] != nil
    }

    private func userDataDir(_ appPath: String) -> String? {
        guard let id = BundleInfo.identifier(appPath),
              let sub = ChromiumAdapter.userDataDirs[id] else { return nil }
        let support = FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Application Support"
        return support + "/" + sub
    }

    /// Reads `Local State` → profile.info_cache as an ordered [directory: displayName].
    private func directoryNames(_ appPath: String) -> [(dir: String, name: String)] {
        guard let dir = userDataDir(appPath),
              let data = FileManager.default.contents(atPath: dir + "/Local State"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }
        return cache.compactMap { key, value in
            guard let info = value as? [String: Any] else { return nil }
            let name = (info["name"] as? String) ?? key
            return (key, name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func profiles(appPath: String) -> [BrowserProfile] {
        let entries = directoryNames(appPath)
        let nameCounts = Dictionary(grouping: entries, by: { $0.name }).mapValues(\.count)
        return entries.map { entry in
            // Disambiguate duplicate display names by appending the directory.
            let label = (nameCounts[entry.name] ?? 0) > 1
                ? "\(entry.name) (\(entry.dir))"
                : entry.name
            return BrowserProfile(key: entry.dir, label: label)
        }
    }

    /// Accepts either a directory key ("Profile 1") or a display name ("Work").
    private func resolveDirectory(_ key: String, appPath: String) -> String? {
        let entries = directoryNames(appPath)
        if entries.contains(where: { $0.dir == key }) { return key }
        return entries.first { $0.name == key }?.dir
    }

    func launchSpec(appPath: String, profileKey: String?, openMode: OpenMode, url: URL) -> LaunchSpec {
        var args: [String] = []
        if let key = profileKey, !key.isEmpty,
           let dir = resolveDirectory(key, appPath: appPath) {
            args.append("--profile-directory=" + dir)
        }
        // Chromium opens a new tab by default; --new-window forces a window. (No --new-tab flag.)
        if openMode == .newWindow { args.append("--new-window") }
        args.append(url.absoluteString)
        return LaunchSpec(executable: BundleInfo.binary(appPath), arguments: args)
    }
}

// MARK: - Everything else (Safari, etc.) — open without profile selection

struct GenericAdapter: BrowserAdapter {
    var hasProfileSupport: Bool { false }
    var hasOpenModeSupport: Bool { false }
    func handles(appPath: String) -> Bool { true }
    func profiles(appPath: String) -> [BrowserProfile] { [] }

    func launchSpec(appPath: String, profileKey: String?, openMode: OpenMode, url: URL) -> LaunchSpec {
        // No reliable per-profile or tab/window control (e.g. Safari) — just open the URL.
        LaunchSpec(executable: "/usr/bin/open", arguments: ["-a", appPath, url.absoluteString])
    }
}
